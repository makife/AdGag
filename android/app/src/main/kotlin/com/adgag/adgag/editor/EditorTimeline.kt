package com.adgag.adgag.editor

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

/**
 * A real, functional timeline — direct response to a user report that
 * the previous version ("just a trim slider") wasn't one:
 * [thumbnails][EditorViewModel.thumbnails] across the Clip row, a
 * read-only playhead, two draggable trim handles, and (once music is
 * attached) a Music row that can be both repositioned (drag its body)
 * and shortened (drag its own right edge) — see
 * [EditorViewModel.setMusicPlacement]'s own doc comment for exactly
 * what "cutting" the music means in this phase.
 *
 * Deliberately does NOT horizontally scroll: this app's own hard
 * 10-second clip cap (CLAUDE.md section 4) means the *entire* timeline
 * comfortably fits one screen width at a fixed scale — [BoxWithConstraints]
 * simply divides the available width by [EditorViewModel.durationMs],
 * filling exactly the space given. This sidesteps an entire category of
 * risk this project has been burned by before (a scrolling timeline
 * whose auto-follow-during-playback fed back into seeking, causing a
 * severe stutter in the Flutter editor this replaces — see that
 * investigation's own CLAUDE.md history) rather than reintroducing it
 * in Kotlin without any way to test it on a device first.
 *
 * Gesture design, all one-directional (no feedback loops):
 * - Player position -> playhead: read-only polling ([rememberPlayheadPositionMs]),
 *   never writes back to the player.
 * - User drag on the clip body -> seeks the player directly. Never the
 *   reverse.
 * - Dragging a handle updates ONLY local Compose state continuously (so
 *   the drag feels immediate); the real, comparatively expensive
 *   [EditorViewModel] mutation (which rebuilds and reloads the whole
 *   native [androidx.media3.exoplayer.ExoPlayer] preview MediaSource)
 *   only fires once, on drag END — not on every pixel of movement.
 *
 * A real, specific Compose pitfall avoided deliberately, not by luck:
 * every drag handle's `pointerInput` block is keyed on `Unit` (so an
 * in-flight drag is never cancelled mid-gesture by an unrelated
 * recomposition) — which means the gesture-detection coroutine is set
 * up ONCE and would otherwise keep calling whichever `onDrag`/`onDragEnd`
 * LAMBDA INSTANCE existed at that first composition forever, ignoring
 * every newer one a recomposition creates. [rememberUpdatedState] is
 * used everywhere a handle receives a callback, specifically to avoid
 * that — without it, drag handles would visually work on the very
 * first attempt and then silently stop responding to committed state
 * changes on every attempt after, a bug that would never show up in a
 * quick code read and would only ever surface on a real device.
 */
@Composable
fun EditorTimeline(viewModel: EditorViewModel, modifier: Modifier = Modifier) {
    val density = LocalDensity.current
    val positionMs = rememberPlayheadPositionMs(viewModel)

    Column(modifier = modifier) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(text = "Clip", color = AdGagColors.OnSurfaceMuted, style = MaterialTheme.typography.labelMedium)
            Text(
                text = "${formatSeconds(viewModel.trimStartMs)} – ${formatSeconds(viewModel.trimEndMs)}",
                color = AdGagColors.OnSurfaceMuted,
                style = MaterialTheme.typography.labelMedium,
            )
        }
        Spacer(modifier = Modifier.height(AdGagSpacing.xs.dp))

        ClipRow(viewModel = viewModel, density = density, positionMs = positionMs)

        if (viewModel.musicUri != null && viewModel.musicDurationMs != null) {
            Spacer(modifier = Modifier.height(AdGagSpacing.sm.dp))
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(text = "Music", color = AdGagColors.OnSurfaceMuted, style = MaterialTheme.typography.labelMedium)
                Text(
                    text = "${formatSeconds(viewModel.musicStartOffsetMs)} – " +
                        formatSeconds(viewModel.musicStartOffsetMs + viewModel.musicPlayDurationMs),
                    color = AdGagColors.OnSurfaceMuted,
                    style = MaterialTheme.typography.labelMedium,
                )
            }
            Spacer(modifier = Modifier.height(AdGagSpacing.xs.dp))
            MusicRow(viewModel = viewModel, density = density)
        }
    }
}

private const val ClipRowHeightDp = 64
private const val MusicRowHeightDp = 32
private const val HandleWidthDp = 16

/** Real touch target, centered on the visible handle — the Flutter editor's own research (img.ly's mobile-timeline article) found a too-small hit area was the actual cause of "resize handles don't work" complaints there; applying that lesson from the start here instead of rediscovering it. */
private const val HandleHitWidthDp = 32
private const val MinTrimGapMs = 500L

@Composable
private fun ClipRow(viewModel: EditorViewModel, density: Density, positionMs: Long) {
    BoxWithConstraints(
        modifier = Modifier
            .fillMaxWidth()
            .height(ClipRowHeightDp.dp)
            .clip(RoundedCornerShape(AdGagRadius.sm.dp))
            .background(AdGagColors.Surface),
    ) {
        val fullWidthPx = with(density) { maxWidth.toPx() }
        val durationMs = viewModel.durationMs.coerceAtLeast(1L)
        fun msToPx(ms: Long): Float = (ms.toFloat() / durationMs) * fullWidthPx
        // Absolute position -> time, clamped to the clip's own range —
        // correct for the scrub/tap gestures below (an actual point on
        // the timeline), but NOT for a drag DELTA (see pxDeltaToMs).
        fun pxToMs(px: Float): Long = ((px / fullWidthPx) * durationMs).toLong().coerceIn(0L, durationMs)
        // REAL BUG caught before ever reaching a device: a drag delta
        // can legitimately be negative (dragging left/up-the-timeline).
        // Reusing pxToMs's absolute-position clamp for a delta would
        // floor every negative delta to 0 — silently breaking every
        // leftward drag on both trim handles. This one is deliberately
        // unclamped; the resulting localTrimStart/localTrimEnd values
        // are what get clamped, not the raw delta itself.
        fun pxDeltaToMsDelta(deltaPx: Float): Long = ((deltaPx / fullWidthPx) * durationMs).toLong()

        // Local, live-updating drag state for both trim handles — kept
        // in THIS composable (not inside TrimHandle itself), separate
        // from viewModel.trimStartMs/trimEndMs, so a drag never
        // triggers the real (expensive) composition rebuild on every
        // pixel of movement; only committed via viewModel.setTrim on
        // drag end. Reset to the committed value whenever it changes
        // from elsewhere (e.g. after that commit actually lands).
        var localTrimStart by remember(viewModel.trimStartMs) { mutableLongStateOf(viewModel.trimStartMs) }
        var localTrimEnd by remember(viewModel.trimEndMs) { mutableLongStateOf(viewModel.trimEndMs) }

        // Thumbnails, tiled evenly across the full width — best-effort:
        // an empty list (generation still running, or failed) just
        // leaves the plain Surface-colored track visible underneath,
        // never blocks or breaks the row.
        if (viewModel.thumbnails.isNotEmpty()) {
            Row(modifier = Modifier.fillMaxSize()) {
                viewModel.thumbnails.forEach { bitmap ->
                    Image(
                        bitmap = bitmap.asImageBitmap(),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.weight(1f).fillMaxHeight(),
                    )
                }
            }
        }

        // Scrims over the excluded (outside-trim) portions — dims what's
        // cut rather than filling what's kept, the same convention the
        // Flutter editor's own research settled on for exactly this
        // (native gallery editors dim the excluded range, not highlight
        // the kept one). Driven by the LOCAL drag state so this updates
        // live while dragging, not only after a commit.
        val trimStartPx = msToPx(localTrimStart)
        val trimEndPx = msToPx(localTrimEnd)
        if (trimStartPx > 0f) {
            Box(
                modifier = Modifier
                    .width(with(density) { trimStartPx.toDp() })
                    .fillMaxHeight()
                    .background(AdGagColors.OverlayScrim),
            )
        }
        if (trimEndPx < fullWidthPx) {
            Box(
                modifier = Modifier
                    .offset(x = with(density) { trimEndPx.toDp() })
                    .width(with(density) { (fullWidthPx - trimEndPx).toDp() })
                    .fillMaxHeight()
                    .background(AdGagColors.OverlayScrim),
            )
        }

        // Scrub: drag (or tap) anywhere on the clip body seeks directly.
        // This Box never moves/resizes itself, so change.position (local
        // to this pointerInput node) is always a stable, meaningful X —
        // unlike the handles below, no moving-target coordinate issue
        // here. One-directional: never reads position back out of this
        // gesture, only ever calls seekTo.
        //
        // COORDINATE SYSTEMS (the root cause of the trim-handle bugs):
        // this row draws SOURCE time (0 = start of the original file),
        // but the preview player is a ClippingMediaSource whose position
        // is CLIP time (0 = trimStartMs). Every seek must convert source
        // -> clip, clamped to the kept window — seeking the raw source
        // time used to land past the clip's end after a left trim. The
        // trim values are read from viewModel at event time (not
        // captured), since this pointerInput is only keyed on durationMs.
        fun seekToSourceMs(sourceMs: Long) {
            val start = viewModel.trimStartMs
            val end = if (viewModel.trimEndMs > start) viewModel.trimEndMs else durationMs
            viewModel.player.seekTo(sourceMs.coerceIn(start, end) - start)
        }
        Box(
            modifier = Modifier
                .fillMaxSize()
                .pointerInput(durationMs) {
                    detectDragGestures { change, _ ->
                        change.consume()
                        seekToSourceMs(pxToMs(change.position.x))
                    }
                }
                .pointerInput(durationMs) {
                    detectTapGestures { offset -> seekToSourceMs(pxToMs(offset.x)) }
                },
        )

        // Playhead — purely a read-only indicator of
        // rememberPlayheadPositionMs's polled value; never itself
        // triggers a seek. Colored with the brand gradient per direct
        // user request ("timeline ilerleme çizgisini renkli yapalım"),
        // replacing the previous plain white line.
        // positionMs is CLIP time (see seekToSourceMs above) — shift it
        // by the trim start to draw it in this row's SOURCE-time space,
        // and keep it inside the kept window (the live local window
        // while a handle is being dragged). Drawing raw clip time here
        // is why the playhead ran across the dimmed, cut-away region.
        val playheadSourceMs = (viewModel.trimStartMs + positionMs).coerceIn(localTrimStart, localTrimEnd)
        Box(
            modifier = Modifier
                .offset(x = with(density) { msToPx(playheadSourceMs).toDp() } - 1.dp)
                .width(3.dp)
                .fillMaxHeight()
                .background(AdGagColors.BrandGradient),
        )

        TrimHandle(
            xPx = trimStartPx,
            rowWidthPx = fullWidthPx,
            density = density,
            onDrag = { deltaPx ->
                val deltaMs = pxDeltaToMsDelta(deltaPx)
                localTrimStart = (localTrimStart + deltaMs).coerceIn(0L, localTrimEnd - MinTrimGapMs)
            },
            onDragEnd = { viewModel.setTrim(localTrimStart, localTrimEnd) },
        )
        TrimHandle(
            xPx = trimEndPx,
            rowWidthPx = fullWidthPx,
            density = density,
            onDrag = { deltaPx ->
                val deltaMs = pxDeltaToMsDelta(deltaPx)
                localTrimEnd = (localTrimEnd + deltaMs).coerceIn(localTrimStart + MinTrimGapMs, durationMs)
            },
            onDragEnd = { viewModel.setTrim(localTrimStart, localTrimEnd) },
        )
    }
}

/**
 * A draggable trim handle. Takes the CURRENT pixel position as a plain
 * parameter (for where to draw itself) and reports raw pixel DELTAS
 * upward via [onDrag] — it deliberately holds no position state of its
 * own; the caller ([ClipRow]) owns that, so there's exactly one source
 * of truth per handle, not two that could disagree.
 *
 * [dragAmount] (the delta since the LAST callback, in the parent's
 * coordinate space) is used instead of `change.position` (which is
 * local to this Box's own shifting bounds, since this Box's offset
 * changes as [xPx] changes) — using `change.position` here would be
 * measuring against a moving coordinate origin mid-gesture, a real bug
 * class distinct from the stale-closure one described on
 * [EditorTimeline]'s own doc comment.
 */
@Composable
private fun TrimHandle(
    xPx: Float,
    rowWidthPx: Float,
    density: Density,
    onDrag: (deltaPx: Float) -> Unit,
    onDragEnd: () -> Unit,
) {
    val currentOnDrag by rememberUpdatedState(onDrag)
    val currentOnDragEnd by rememberUpdatedState(onDragEnd)
    // Centered on xPx, but kept fully inside the row: at the row's very
    // edges (the default, untrimmed state for both handles) a centered
    // hit box would sit half outside its parent, where Compose never
    // delivers touches — leaving only a sliver grabbable, and a near
    // miss landing on the scrub layer (a seek, not a trim) instead.
    val hitWidthPx = with(density) { HandleHitWidthDp.dp.toPx() }
    val hitLeftPx = (xPx - hitWidthPx / 2).coerceIn(0f, (rowWidthPx - hitWidthPx).coerceAtLeast(0f))
    Box(
        modifier = Modifier
            .offset(x = with(density) { hitLeftPx.toDp() })
            .width(HandleHitWidthDp.dp)
            .fillMaxHeight()
            .pointerInput(Unit) {
                detectDragGestures(
                    onDragEnd = { currentOnDragEnd() },
                    onDrag = { change, dragAmount ->
                        change.consume()
                        currentOnDrag(dragAmount.x)
                    },
                )
            },
        contentAlignment = Alignment.CenterStart,
    ) {
        // The visible bar stays centered on the real trim point even when
        // the hit box above got pushed inward at a row edge (clamped so
        // the bar itself never leaves the row either).
        val barWidthPx = with(density) { HandleWidthDp.dp.toPx() }
        val barLeftPx = (xPx - barWidthPx / 2 - hitLeftPx).coerceIn(0f, hitWidthPx - barWidthPx)
        Box(
            modifier = Modifier
                .offset(x = with(density) { barLeftPx.toDp() })
                .width(HandleWidthDp.dp)
                .fillMaxHeight()
                .clip(RoundedCornerShape(AdGagRadius.sm.dp))
                .background(AdGagColors.GradientPink),
        )
    }
}

@Composable
private fun MusicRow(viewModel: EditorViewModel, density: Density) {
    BoxWithConstraints(
        modifier = Modifier
            .fillMaxWidth()
            .height(MusicRowHeightDp.dp)
            .clip(RoundedCornerShape(AdGagRadius.sm.dp))
            .background(AdGagColors.Surface),
    ) {
        val fullWidthPx = with(density) { maxWidth.toPx() }
        val clipDurationMs = (viewModel.trimEndMs - viewModel.trimStartMs).coerceAtLeast(1L)
        fun msToPx(ms: Long): Float = (ms.toFloat() / clipDurationMs) * fullWidthPx
        // Deliberately unclamped — this is only ever used to convert a
        // drag DELTA (which can legitimately be negative), never an
        // absolute position. See ClipRow's own pxDeltaToMsDelta for the
        // exact bug this distinction avoids.
        fun pxDeltaToMsDelta(deltaPx: Float): Long = (deltaPx / fullWidthPx * clipDurationMs).toLong()

        var localStart by remember(viewModel.musicStartOffsetMs) { mutableLongStateOf(viewModel.musicStartOffsetMs) }
        var localDuration by remember(viewModel.musicPlayDurationMs) { mutableLongStateOf(viewModel.musicPlayDurationMs) }
        val minWidthPx = with(density) { HandleHitWidthDp.dp.toPx() }
        val segmentStartPx = msToPx(localStart)
        val segmentWidthPx = msToPx(localDuration).coerceAtLeast(minWidthPx)

        val commitPlacement by rememberUpdatedState({ viewModel.setMusicPlacement(localStart, localDuration) })
        val musicFileDurationMs = viewModel.musicDurationMs ?: Long.MAX_VALUE
        // Real bug (user report: after shortening the music once it could
        // not be dragged back to its old length, and the video froze):
        // localStart/localDuration are re-created by remember(key) every
        // time a commit lands, but the pointerInput(Unit) gesture blocks
        // below are set up ONCE — their inline lambdas kept writing to the
        // FIRST composition's state objects (and its clipDurationMs /
        // width), so every drag after the first moved nothing on screen
        // and then committed the unchanged values, forcing a pointless
        // player rebuild. Routed through rememberUpdatedState — the same
        // pattern TrimHandle already uses — so gestures always act on the
        // current state.
        val onBodyDrag by rememberUpdatedState({ deltaPx: Float ->
            val deltaMs = pxDeltaToMsDelta(deltaPx)
            localStart = (localStart + deltaMs).coerceIn(0L, (clipDurationMs - localDuration).coerceAtLeast(0L))
        })
        val onEdgeDrag by rememberUpdatedState({ deltaPx: Float ->
            val deltaMs = pxDeltaToMsDelta(deltaPx)
            val maxMs = minOf(musicFileDurationMs, clipDurationMs - localStart).coerceAtLeast(MinTrimGapMs)
            localDuration = (localDuration + deltaMs).coerceIn(MinTrimGapMs, maxMs)
        })

        // Segment body: dragging moves the WHOLE segment (repositions
        // when the music starts within the clip) without changing its
        // length. dragAmount (delta), not change.position, for the same
        // moving-coordinate-origin reason TrimHandle avoids it.
        Box(
            modifier = Modifier
                .offset(x = with(density) { segmentStartPx.toDp() })
                .width(with(density) { segmentWidthPx.toDp() })
                .fillMaxHeight()
                .clip(RoundedCornerShape(AdGagRadius.sm.dp))
                .background(AdGagColors.GradientBlue.copy(alpha = 0.55f))
                .pointerInput(Unit) {
                    detectDragGestures(
                        onDragEnd = { commitPlacement() },
                        onDrag = { change, dragAmount ->
                            change.consume()
                            onBodyDrag(dragAmount.x)
                        },
                    )
                },
        )

        // Right-edge handle: dragging shortens/lengthens how much of the
        // song plays (from the song's own start) — this is what "cutting"
        // the music means in this phase; see setMusicPlacement's doc
        // comment.
        Box(
            modifier = Modifier
                .offset(x = with(density) { (segmentStartPx + segmentWidthPx).toDp() } - (HandleHitWidthDp / 2).dp)
                .width(HandleHitWidthDp.dp)
                .fillMaxHeight()
                .pointerInput(Unit) {
                    detectDragGestures(
                        onDragEnd = { commitPlacement() },
                        onDrag = { change, dragAmount ->
                            change.consume()
                            onEdgeDrag(dragAmount.x)
                        },
                    )
                },
            contentAlignment = Alignment.CenterEnd,
        ) {
            Box(
                modifier = Modifier
                    .width(HandleWidthDp.dp)
                    .fillMaxHeight()
                    .clip(RoundedCornerShape(AdGagRadius.sm.dp))
                    .background(AdGagColors.GradientPink),
            )
        }
    }
}

/**
 * [ExoPlayer] doesn't push continuous position
 * updates through [androidx.media3.common.Player.Listener] — position
 * must be polled. This is read-only: it never writes back to the
 * player, only reads, so it cannot participate in the position-drives-
 * scroll-drives-seek feedback loop class of bug this project has
 * already been burned by once (in the Flutter editor this native screen
 * replaces).
 */
@Composable
private fun rememberPlayheadPositionMs(viewModel: EditorViewModel): Long {
    var position by remember { mutableLongStateOf(0L) }
    // Polls continuously, not only while playing: a scrub or a trim
    // commit while PAUSED also moves the position, and the playhead used
    // to stay frozen at its old spot until playback resumed.
    // currentPosition is a cheap getter; 50ms keeps the line smooth.
    LaunchedEffect(viewModel) {
        while (true) {
            position = viewModel.player.currentPosition
            delay(50)
        }
    }
    return position
}

private fun formatSeconds(ms: Long): String {
    val totalSeconds = ms / 1000
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "%d:%02d".format(minutes, seconds)
}
