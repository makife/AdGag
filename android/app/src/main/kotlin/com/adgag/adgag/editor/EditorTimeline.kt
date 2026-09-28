package com.adgag.adgag.editor

import android.graphics.Bitmap
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.Icon
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.media3.common.util.UnstableApi
import kotlinx.coroutines.delay

/**
 * Multi-clip timeline, top to bottom:
 * 1. Clip strip — every clip's kept part side by side (width ∝ kept
 *    duration, GLOBAL time), an effect button on each boundary, and a
 *    "+" at the right end that records another clip until the 30s cap.
 *    Tap selects a clip (and seeks there); drag scrubs.
 * 2. Trim row for the SELECTED clip — its whole SOURCE with scrims over
 *    the cut parts and two handles.
 * 3. Music row (once music is attached) — on the GLOBAL timeline,
 *    aligned under the clip strip; trim handles on both ends, drag the
 *    middle to move it.
 * 4. Song row — the whole song, any length; the used section is a
 *    fixed-length window slid anywhere in the song.
 *
 * Fits one screen width (≤30s) — no horizontal scrolling, which avoids
 * the scroll/seek feedback-loop bug class the old Flutter editor had.
 *
 * Gesture rule, learned the hard way twice in this file's history:
 * `pointerInput(Unit)` blocks are set up once, so anything they touch
 * that changes over time (remember(key) state, recomputed widths,
 * callbacks) must go through [rememberUpdatedState].
 */
@UnstableApi
@Composable
fun EditorTimeline(
    viewModel: EditorViewModel,
    onAddClip: () -> Unit,
    onPickTransition: (boundaryIndex: Int) -> Unit,
    onOpenMusic: () -> Unit,
    onAddText: () -> Unit = {},
    onEditText: (String) -> Unit = {},
    onAddSpeedRange: () -> Unit = {},
    onEditSpeedRange: (String) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val density = LocalDensity.current
    val positionMs = rememberGlobalPositionMs(viewModel)

    Column(modifier = modifier) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(text = tr("Clips"), color = AdGagColors.OnSurfaceMuted, style = MaterialTheme.typography.labelMedium)
            Text(
                // OUTPUT length — what the 30s cap applies to (differs from the strip under slow motion).
                text = (if (viewModel.speedRanges.isNotEmpty()) tr("slow-mo") + " · " else "") +
                    "${formatSeconds(viewModel.outputDurationMs)} / ${formatSeconds(MaxTotalDurationMs)}",
                color = AdGagColors.OnSurfaceMuted,
                style = MaterialTheme.typography.labelMedium,
            )
        }
        Spacer(modifier = Modifier.height(AdGagSpacing.xs.dp))
        AlignedRow(trailing = { AddClipButton(enabled = viewModel.canAddClip, onClick = onAddClip) }) {
            ClipStrip(viewModel, density, positionMs, onPickTransition)
        }

        val selected = viewModel.selectedClipIndex
        val clip = viewModel.clips.getOrNull(selected)
        if (clip != null) {
            Spacer(modifier = Modifier.height(AdGagSpacing.sm.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = if (viewModel.clips.size > 1) tr("Clip {0} · trim", selected + 1) else tr("Trim"),
                    color = AdGagColors.OnSurfaceMuted,
                    style = MaterialTheme.typography.labelMedium,
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = "${formatSeconds(clip.trimStartMs)} – ${formatSeconds(clip.trimEndMs)}",
                        color = AdGagColors.OnSurfaceMuted,
                        style = MaterialTheme.typography.labelMedium,
                    )
                    if (viewModel.clips.size > 1) {
                        Spacer(modifier = Modifier.width(AdGagSpacing.md.dp))
                        Text(
                            text = tr("Delete clip"),
                            color = AdGagColors.Danger,
                            style = MaterialTheme.typography.labelMedium,
                            modifier = Modifier.clickable { viewModel.removeClip(selected) },
                        )
                    }
                }
            }
            Spacer(modifier = Modifier.height(AdGagSpacing.xs.dp))
            TrimRow(viewModel, selected, clip, density, positionMs)
        }

        if (viewModel.speedRanges.isNotEmpty()) {
            val selRange = viewModel.speedRanges.firstOrNull { it.id == viewModel.selectedSpeedRangeId }
            Spacer(modifier = Modifier.height(AdGagSpacing.sm.dp))
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(
                    text = if (selRange != null) tr("Slow motion") + " · ${formatSpeed(selRange.speed)}" else tr("Slow motion · tap one to select"),
                    color = AdGagColors.OnSurfaceMuted,
                    style = MaterialTheme.typography.labelMedium,
                )
                if (selRange != null) {
                    Text(
                        text = "${formatPreciseSeconds(selRange.startMs)} – ${formatPreciseSeconds(selRange.endMs)}",
                        color = AdGagColors.OnSurfaceMuted,
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
            }
            Spacer(modifier = Modifier.height(AdGagSpacing.xs.dp))
            // Same layout (and SOURCE time scale) as the clip strip, so a
            // range sits right under the footage it slows down.
            AlignedRow(trailing = { AddRowItemButton(contentDescription = tr("Add slow motion"), onClick = onAddSpeedRange) }) {
                SpeedRow(viewModel, density, positionMs, onEditSpeedRange)
            }
        }

        if (viewModel.textLayers.isNotEmpty() || viewModel.stickerLayers.isNotEmpty() || viewModel.soundLayers.isNotEmpty()) {
            val sel = overlayBars(viewModel).firstOrNull { it.id == viewModel.selectedTextId }
            Spacer(modifier = Modifier.height(AdGagSpacing.sm.dp))
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(
                    text = if (sel != null) "${sel.kind} · \"${sel.label.take(18)}\"" else tr("Text, stickers & sounds · tap one to select"),
                    color = AdGagColors.OnSurfaceMuted,
                    style = MaterialTheme.typography.labelMedium,
                    maxLines = 1,
                )
                if (sel != null) {
                    Text(
                        text = "${formatSeconds(sel.startMs)} – ${formatSeconds(sel.endMs)}",
                        color = AdGagColors.OnSurfaceMuted,
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
            }
            Spacer(modifier = Modifier.height(AdGagSpacing.xs.dp))
            AlignedRow(trailing = { AddRowItemButton(contentDescription = tr("Add text"), onClick = onAddText) }) {
                TextRow(viewModel, density, onEditText)
            }
        }

        if (viewModel.musicPath != null && viewModel.musicDurationMs != null) {
            Spacer(modifier = Modifier.height(AdGagSpacing.sm.dp))
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(
                    text = tr("Music") +
                        (if (viewModel.musicSpeed != 1f) " · ${formatSpeed(viewModel.musicSpeed)}" else "") +
                        (if (viewModel.musicLoop) " · " + tr("loop") else ""),
                    color = AdGagColors.OnSurfaceMuted,
                    style = MaterialTheme.typography.labelMedium,
                )
                Text(
                    text = "${formatSeconds(viewModel.musicStartOffsetMs)} – " +
                        formatSeconds(viewModel.musicStartOffsetMs + viewModel.musicPlayDurationMs),
                    color = AdGagColors.OnSurfaceMuted,
                    style = MaterialTheme.typography.labelMedium,
                )
            }
            Spacer(modifier = Modifier.height(AdGagSpacing.xs.dp))
            // Same row layout as the clip strip (so the same width and time
            // scale); the slot under "+" holds the music settings button.
            AlignedRow(trailing = { MusicSettingsButton(onClick = onOpenMusic) }) { MusicRow(viewModel, density) }

            // The WHOLE song, whatever its length, with the used section as
            // a window — pick e.g. 0:45–1:15 of a 3-minute track.
            val songMs = viewModel.musicDurationMs ?: 0L
            Spacer(modifier = Modifier.height(AdGagSpacing.sm.dp))
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(text = tr("Song section"), color = AdGagColors.OnSurfaceMuted, style = MaterialTheme.typography.labelMedium)
                Text(
                    text = "${formatSeconds(viewModel.musicSourceStartMs)} – " +
                        tr("{0} of {1}", formatSeconds(viewModel.musicSourceStartMs + viewModel.musicPlayDurationMs), formatSeconds(songMs)),
                    color = AdGagColors.OnSurfaceMuted,
                    style = MaterialTheme.typography.labelMedium,
                )
            }
            Spacer(modifier = Modifier.height(AdGagSpacing.xs.dp))
            SongRow(viewModel, density, positionMs)
        }
    }
}

private const val SongRowHeightDp = 40
private const val SongTickEveryMs = 10_000L

/**
 * The whole song at full width, the used section as a window of FIXED
 * length (the music's play length — by default the video's length; resize
 * it on the music row above). Drag ANYWHERE on this row to slide the
 * window through the song, or tap to centre it there — e.g. any 5 seconds
 * of a 3-minute song for a 5-second video.
 *
 * Deliberately no edge handles here: on a long song the window is only a
 * few pixels wide and two 32dp handle hit areas swallowed it completely,
 * so every drag resized instead of moved (user report). Only the song
 * in-point changes; where the music sits in the video stays put.
 */
@UnstableApi
@Composable
private fun SongRow(viewModel: EditorViewModel, density: Density, globalPositionMs: Long) {
    val songMs = (viewModel.musicDurationMs ?: 0L).coerceAtLeast(1L)
    BoxWithConstraints(
        modifier = Modifier
            .fillMaxWidth()
            .height(SongRowHeightDp.dp)
            .clip(RoundedCornerShape(AdGagRadius.sm.dp))
            .background(AdGagColors.Surface),
    ) {
        val widthPx = with(density) { maxWidth.toPx() }
        fun msToPx(ms: Long): Float = ms.toFloat() / songMs * widthPx

        var localSource by remember(viewModel.musicSourceStartMs) { mutableLongStateOf(viewModel.musicSourceStartMs) }
        val sectionMs = viewModel.musicPlayDurationMs.coerceIn(0L, songMs)
        val maxSource = (songMs - sectionMs).coerceAtLeast(0L)

        val commit by rememberUpdatedState({
            viewModel.setMusicPlacement(viewModel.musicStartOffsetMs, localSource, viewModel.musicPlayDurationMs)
        })
        val onDrag by rememberUpdatedState({ deltaPx: Float ->
            val deltaMs = (deltaPx / widthPx * songMs).toLong()
            localSource = (localSource + deltaMs).coerceIn(0L, maxSource)
        })
        val onTap by rememberUpdatedState({ xPx: Float ->
            val centerMs = (xPx / widthPx * songMs).toLong()
            localSource = (centerMs - sectionMs / 2).coerceIn(0L, maxSource)
        })

        // The whole row is the touch target (see the doc comment).
        Box(
            modifier = Modifier
                .fillMaxSize()
                .pointerInput(Unit) {
                    detectDragGestures(
                        onDragEnd = { commit() },
                        onDrag = { change, dragAmount ->
                            change.consume()
                            onDrag(dragAmount.x)
                        },
                    )
                }
                .pointerInput(Unit) {
                    detectTapGestures { offset ->
                        onTap(offset.x)
                        commit()
                    }
                },
        )

        // 10-second ticks so long songs can be navigated by eye.
        var tick = SongTickEveryMs
        while (tick < songMs) {
            Box(
                modifier = Modifier
                    .offset(x = with(density) { msToPx(tick).toDp() })
                    .width(1.dp)
                    .fillMaxHeight()
                    .background(AdGagColors.Border),
            )
            tick += SongTickEveryMs
        }

        // The window — at least a few dp wide so a short section on a long
        // song is still visible, centred on its real position.
        val minWindowPx = with(density) { 6.dp.toPx() }
        val realStartPx = msToPx(localSource)
        val realWidthPx = msToPx(sectionMs)
        val drawWidthPx = realWidthPx.coerceAtLeast(minWindowPx)
        val drawStartPx = (realStartPx - (drawWidthPx - realWidthPx) / 2).coerceIn(0f, (widthPx - drawWidthPx).coerceAtLeast(0f))
        Box(
            modifier = Modifier
                .offset(x = with(density) { drawStartPx.toDp() })
                .width(with(density) { drawWidthPx.toDp() })
                .fillMaxHeight()
                .clip(RoundedCornerShape(AdGagRadius.sm.dp))
                .background(AdGagColors.Accent.copy(alpha = 0.75f)),
        )

        // Where in the SONG the preview is right now (only while the music plays).
        val outMs = viewModel.toOutputMs(globalPositionMs) - viewModel.musicStartOffsetMs
        if (viewModel.musicPlayDurationMs > 0 && outMs in 0 until viewModel.musicCoveredMs) {
            val songPos = viewModel.musicSourceStartMs + outMs % viewModel.musicPlayDurationMs
            Box(
                modifier = Modifier
                    .offset(x = with(density) { msToPx(songPos).toDp() } - 1.dp)
                    .width(2.dp)
                    .fillMaxHeight()
                    .background(Color.White),
            )
        }
    }
}

private const val StripHeightDp = 56
private const val TrimRowHeightDp = 56
private const val MusicRowHeightDp = 32
private const val HandleWidthDp = 16
private const val AddButtonSizeDp = 48
private const val TransitionButtonSizeDp = 28

/** Touch target around the visible handle (img.ly's mobile-timeline research: too-small hit areas were the cause of "handles don't work"). */
private const val HandleHitWidthDp = 32
private const val MinTrimGapMs = 500L

/** Keeps the clip strip and music row the same width (so the same time scale) whether or not the trailing "+" is shown. */
@Composable
private fun AlignedRow(trailing: (@Composable () -> Unit)?, content: @Composable RowScope.() -> Unit) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Row(modifier = Modifier.weight(1f)) { content() }
        Spacer(modifier = Modifier.width(AdGagSpacing.sm.dp))
        Box(modifier = Modifier.size(AddButtonSizeDp.dp), contentAlignment = Alignment.Center) {
            trailing?.invoke()
        }
    }
}

@Composable
private fun MusicSettingsButton(onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(width = AddButtonSizeDp.dp, height = MusicRowHeightDp.dp)
            .clip(RoundedCornerShape(AdGagRadius.sm.dp))
            .background(AdGagColors.Surface)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = Icons.Filled.Tune,
            contentDescription = tr("Music settings"),
            tint = AdGagColors.OnBackground,
            modifier = Modifier.size(18.dp),
        )
    }
}

@Composable
private fun AddClipButton(enabled: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(AddButtonSizeDp.dp)
            .clip(RoundedCornerShape(AdGagRadius.sm.dp))
            .background(if (enabled) AdGagColors.Accent else AdGagColors.Border)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(imageVector = Icons.Filled.Add, contentDescription = tr("Record another clip"), tint = AdGagColors.OnBackground)
    }
}

@UnstableApi
@Composable
private fun RowScope.ClipStrip(
    viewModel: EditorViewModel,
    density: Density,
    positionMs: Long,
    onPickTransition: (Int) -> Unit,
) {
    BoxWithConstraints(
        modifier = Modifier
            .weight(1f)
            .height(StripHeightDp.dp)
            .clip(RoundedCornerShape(AdGagRadius.sm.dp))
            .background(AdGagColors.Surface),
    ) {
        val widthPx = with(density) { maxWidth.toPx() }
        val total = viewModel.totalDurationMs.coerceAtLeast(1L)
        fun msToPx(ms: Long): Float = ms.toFloat() / total * widthPx

        // Read at event time — these gesture blocks outlive recompositions.
        val currentTotal by rememberUpdatedState(total)
        val currentWidth by rememberUpdatedState(widthPx)
        val pxToGlobalMs = { px: Float -> (px / currentWidth * currentTotal).toLong().coerceIn(0L, currentTotal) }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .pointerInput(Unit) {
                    detectTapGestures { offset ->
                        val g = pxToGlobalMs(offset.x)
                        val index = viewModel.clips.indices.lastOrNull { viewModel.clipStartMs(it) <= g } ?: 0
                        viewModel.selectClip(index)
                        viewModel.seekToGlobal(g)
                    }
                }
                .pointerInput(Unit) {
                    detectDragGestures { change, _ ->
                        change.consume()
                        viewModel.seekToGlobal(pxToGlobalMs(change.position.x))
                    }
                },
        ) {
            Row(modifier = Modifier.fillMaxSize()) {
                viewModel.clips.forEachIndexed { i, clip ->
                    val isSelected = i == viewModel.selectedClipIndex && viewModel.clips.size > 1
                    Box(
                        modifier = Modifier
                            .weight(clip.keptDurationMs.coerceAtLeast(1L).toFloat())
                            .fillMaxHeight()
                            // A hairline gap so clip boundaries read as boundaries.
                            .padding(start = if (i > 0) 1.dp else 0.dp)
                            .clip(RoundedCornerShape(AdGagRadius.sm.dp))
                            .then(
                                if (isSelected) {
                                    Modifier.border(BorderStroke(2.dp, AdGagColors.Accent), RoundedCornerShape(AdGagRadius.sm.dp))
                                } else {
                                    Modifier
                                },
                            ),
                    ) {
                        // Only the frames inside this clip's kept range.
                        val all = viewModel.thumbnails[clip.path].orEmpty()
                        val frames = all.filter { it.first >= clip.trimStartMs - 1 && it.first < clip.trimEndMs }
                            .ifEmpty { all.take(1) }
                        ThumbnailFill(frames.map { it.second })
                    }
                }
            }
        }

        // Effect button on each boundary — tap opens the transition picker.
        for (b in 0 until viewModel.clips.size - 1) {
            val xPx = msToPx(viewModel.clipStartMs(b + 1))
            val active = (viewModel.transitions.getOrNull(b)?.type ?: ClipTransition.NONE) != ClipTransition.NONE
            val sizePx = with(density) { TransitionButtonSizeDp.dp.toPx() }
            Box(
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .offset(x = with(density) { (xPx - sizePx / 2).toDp() })
                    .size(TransitionButtonSizeDp.dp)
                    .clip(CircleShape)
                    .background(if (active) AdGagColors.Accent else AdGagColors.SurfaceElevated)
                    .border(BorderStroke(1.dp, AdGagColors.OnBackground.copy(alpha = 0.6f)), CircleShape)
                    .clickable { onPickTransition(b) },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.AutoAwesome,
                    contentDescription = tr("Transition effect"),
                    tint = AdGagColors.OnBackground,
                    modifier = Modifier.size(16.dp),
                )
            }
        }

        // Global playhead (read-only).
        Box(
            modifier = Modifier
                .offset(x = with(density) { msToPx(positionMs.coerceIn(0L, total)).toDp() } - 1.dp)
                .width(3.dp)
                .fillMaxHeight()
                .background(AdGagColors.BrandGradient),
        )
    }
}

@Composable
private fun ThumbnailFill(bitmaps: List<Bitmap>) {
    if (bitmaps.isEmpty()) return
    Row(modifier = Modifier.fillMaxSize()) {
        bitmaps.forEach { bitmap ->
            Image(
                bitmap = bitmap.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.weight(1f).fillMaxHeight(),
            )
        }
    }
}

/**
 * The selected clip's whole SOURCE, with the cut parts dimmed. Handle
 * drags only move local state; the real rebuild runs once, on release.
 */
@UnstableApi
@Composable
private fun TrimRow(viewModel: EditorViewModel, index: Int, clip: EditorClip, density: Density, globalPositionMs: Long) {
    BoxWithConstraints(
        modifier = Modifier
            .fillMaxWidth()
            .height(TrimRowHeightDp.dp)
            .clip(RoundedCornerShape(AdGagRadius.sm.dp))
            .background(AdGagColors.Surface),
    ) {
        val widthPx = with(density) { maxWidth.toPx() }
        val sourceMs = clip.sourceDurationMs.coerceAtLeast(1L)
        fun msToPx(ms: Long): Float = ms.toFloat() / sourceMs * widthPx
        fun pxDeltaToMsDelta(deltaPx: Float): Long = (deltaPx / widthPx * sourceMs).toLong()

        // Keyed on the clip index too, so selecting another clip resets them.
        var localStart by remember(index, clip.trimStartMs) { mutableLongStateOf(clip.trimStartMs) }
        var localEnd by remember(index, clip.trimEndMs) { mutableLongStateOf(clip.trimEndMs) }
        // How long this clip may be, given the other clips and the 30s cap.
        val maxKeptMs = viewModel.maxKeptMsFor(index).coerceAtLeast(MinTrimGapMs)

        ThumbnailFill(viewModel.thumbnails[clip.path].orEmpty().map { it.second })

        val startPx = msToPx(localStart)
        val endPx = msToPx(localEnd)
        if (startPx > 0f) {
            Box(modifier = Modifier.width(with(density) { startPx.toDp() }).fillMaxHeight().background(AdGagColors.OverlayScrim))
        }
        if (endPx < widthPx) {
            Box(
                modifier = Modifier
                    .offset(x = with(density) { endPx.toDp() })
                    .width(with(density) { (widthPx - endPx).toDp() })
                    .fillMaxHeight()
                    .background(AdGagColors.OverlayScrim),
            )
        }

        // Scrub inside this clip: SOURCE px -> GLOBAL time, clamped to the kept part.
        val scrub by rememberUpdatedState({ px: Float ->
            val sourcePos = (px / widthPx * sourceMs).toLong().coerceIn(clip.trimStartMs, clip.trimEndMs)
            viewModel.seekToGlobal(viewModel.clipStartMs(index) + (sourcePos - clip.trimStartMs))
        })
        // ONE gesture layer for the whole row; what a drag moves is decided
        // where it starts (pickDragTarget): near an edge = that trim edge,
        // anywhere else = scrub. Separate handle hit boxes overlapped on a
        // long source, where the kept 30s is a few dozen px wide — the trim
        // "couldn't be done" (user report).
        val zonePx = with(density) { EdgeZoneDp.dp.toPx() }
        val startDrag by rememberUpdatedState({ x: Float ->
            pickDragTarget(x, msToPx(localStart), msToPx(localEnd), zonePx, bodyMoves = false)
        })
        val drag by rememberUpdatedState({ target: DragTarget, x: Float, deltaPx: Float ->
            when (target) {
                DragTarget.START -> {
                    val lower = (localEnd - maxKeptMs).coerceAtLeast(0L)
                    val upper = (localEnd - MinTrimGapMs).coerceAtLeast(lower)
                    localStart = (localStart + pxDeltaToMsDelta(deltaPx)).coerceIn(lower, upper)
                }
                DragTarget.END -> {
                    val lower = localStart + MinTrimGapMs
                    val upper = minOf(sourceMs, localStart + maxKeptMs).coerceAtLeast(lower)
                    localEnd = (localEnd + pxDeltaToMsDelta(deltaPx)).coerceIn(lower, upper)
                }
                else -> scrub(x)
            }
        })
        val endDrag by rememberUpdatedState({ target: DragTarget ->
            if (target == DragTarget.START || target == DragTarget.END) viewModel.setClipTrim(index, localStart, localEnd)
        })
        Box(
            modifier = Modifier
                .fillMaxSize()
                .pointerInput(Unit) {
                    var target = DragTarget.NONE
                    detectDragGestures(
                        onDragStart = { offset -> target = startDrag(offset.x) },
                        onDragEnd = { endDrag(target) },
                        onDragCancel = { endDrag(target) },
                        onDrag = { change, amount ->
                            change.consume()
                            drag(target, change.position.x, amount.x)
                        },
                    )
                }
                .pointerInput(Unit) { detectTapGestures { offset -> scrub(offset.x) } },
        )

        // Playhead, only while playback is inside this clip.
        val clipStart = viewModel.clipStartMs(index)
        if (globalPositionMs >= clipStart && globalPositionMs < clipStart + clip.keptDurationMs) {
            val sourcePos = (clip.trimStartMs + (globalPositionMs - clipStart)).coerceIn(localStart, localEnd)
            Box(
                modifier = Modifier
                    .offset(x = with(density) { msToPx(sourcePos).toDp() } - 1.dp)
                    .width(3.dp)
                    .fillMaxHeight()
                    .background(AdGagColors.BrandGradient),
            )
        }

        // The visible handles — drawing only; the layer above does the touching.
        HandleBar(xPx = startPx, rowWidthPx = widthPx, density = density)
        HandleBar(xPx = endPx, rowWidthPx = widthPx, density = density)
    }
}

/** What a drag on a row with edges moves — decided where it starts. */
private enum class DragTarget { NONE, START, END, BODY }

/** How close (dp) to an edge a drag must start to grab it. */
private const val EdgeZoneDp = 28

/**
 * Picks what a drag starting at [x] moves on a row whose selection spans
 * [startPx]..[endPx]. Inside the selection the edge zones shrink to a third
 * of its width each, so a narrow selection still has a middle to grab
 * ([bodyMoves]); outside it, the nearer edge within [zonePx] wins.
 */
private fun pickDragTarget(x: Float, startPx: Float, endPx: Float, zonePx: Float, bodyMoves: Boolean): DragTarget {
    if (x > startPx && x < endPx) {
        val inner = if (bodyMoves) minOf(zonePx, (endPx - startPx) / 3) else minOf(zonePx, (endPx - startPx) / 2)
        return when {
            x - startPx <= inner -> DragTarget.START
            endPx - x <= inner -> DragTarget.END
            bodyMoves -> DragTarget.BODY
            else -> DragTarget.NONE
        }
    }
    val toStart = kotlin.math.abs(x - startPx)
    val toEnd = kotlin.math.abs(x - endPx)
    return when {
        minOf(toStart, toEnd) > zonePx -> DragTarget.NONE
        x <= startPx -> DragTarget.START
        x >= endPx -> DragTarget.END
        toStart <= toEnd -> DragTarget.START
        else -> DragTarget.END
    }
}

/** A trim handle's look (pink bar at [xPx], kept inside the row) — no touch handling of its own. */
@Composable
private fun HandleBar(xPx: Float, rowWidthPx: Float, density: Density) {
    val barWidthPx = with(density) { HandleWidthDp.dp.toPx() }
    val leftPx = (xPx - barWidthPx / 2).coerceIn(0f, (rowWidthPx - barWidthPx).coerceAtLeast(0f))
    Box(
        modifier = Modifier
            .offset(x = with(density) { leftPx.toDp() })
            .width(HandleWidthDp.dp)
            .fillMaxHeight()
            .clip(RoundedCornerShape(AdGagRadius.sm.dp))
            .background(AdGagColors.Accent),
    )
}

/**
 * A draggable trim handle. Reports raw drag deltas (the Box moves while
 * dragged, so change.position would be measured against a moving
 * origin). The hit box is clamped inside the row — at the row's edges a
 * centered one would sit half outside its parent, where Compose delivers
 * no touches.
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
        val barWidthPx = with(density) { HandleWidthDp.dp.toPx() }
        val barLeftPx = (xPx - barWidthPx / 2 - hitLeftPx).coerceIn(0f, hitWidthPx - barWidthPx)
        Box(
            modifier = Modifier
                .offset(x = with(density) { barLeftPx.toDp() })
                .width(HandleWidthDp.dp)
                .fillMaxHeight()
                .clip(RoundedCornerShape(AdGagRadius.sm.dp))
                .background(AdGagColors.Accent),
        )
    }
}

/**
 * Music on the GLOBAL timeline. Left handle trims the song's START (the
 * segment's left edge moves, and the song is used from later on), right
 * handle trims its END, and dragging the body moves the whole segment.
 * All three only move local state while dragging; the real (preview-
 * rebuilding) placement is committed once, on release.
 */
@UnstableApi
@Composable
private fun RowScope.MusicRow(viewModel: EditorViewModel, density: Density) {
    BoxWithConstraints(
        modifier = Modifier
            .weight(1f)
            .height(MusicRowHeightDp.dp)
            .clip(RoundedCornerShape(AdGagRadius.sm.dp))
            .background(AdGagColors.Surface),
    ) {
        val widthPx = with(density) { maxWidth.toPx() }
        // Music lives in OUTPUT time; the row spans the whole output, like the strip spans the whole source.
        val totalMs = viewModel.outputDurationMs.coerceAtLeast(1L)
        fun msToPx(ms: Long): Float = ms.toFloat() / totalMs * widthPx
        fun pxDeltaToMsDelta(deltaPx: Float): Long = (deltaPx / widthPx * totalMs).toLong()

        var localStart by remember(viewModel.musicStartOffsetMs) { mutableLongStateOf(viewModel.musicStartOffsetMs) }
        var localSource by remember(viewModel.musicSourceStartMs) { mutableLongStateOf(viewModel.musicSourceStartMs) }
        var localDuration by remember(viewModel.musicPlayDurationMs) { mutableLongStateOf(viewModel.musicPlayDurationMs) }
        val songMs = viewModel.musicDurationMs ?: Long.MAX_VALUE
        val segmentStartPx = msToPx(localStart)
        val segmentEndPx = msToPx(localStart + localDuration)

        // Every gesture below goes through rememberUpdatedState — the
        // pointerInput(Unit) blocks outlive the remember(key) state objects.
        val commit by rememberUpdatedState({ viewModel.setMusicPlacement(localStart, localSource, localDuration) })
        val onBodyDrag by rememberUpdatedState({ deltaPx: Float ->
            localStart = (localStart + pxDeltaToMsDelta(deltaPx)).coerceIn(0L, (totalMs - localDuration).coerceAtLeast(0L))
        })
        val onLeftDrag by rememberUpdatedState({ deltaPx: Float ->
            // Moving the left edge by d: the segment starts d later on the
            // timeline AND d later in the song, and gets d shorter.
            val lower = -minOf(localStart, localSource)
            val upper = (localDuration - MinTrimGapMs).coerceAtLeast(lower)
            val d = pxDeltaToMsDelta(deltaPx).coerceIn(lower, upper)
            localStart += d
            localSource += d
            localDuration -= d
        })
        val onRightDrag by rememberUpdatedState({ deltaPx: Float ->
            val maxMs = minOf(songMs - localSource, totalMs - localStart).coerceAtLeast(MinTrimGapMs)
            localDuration = (localDuration + pxDeltaToMsDelta(deltaPx)).coerceIn(MinTrimGapMs, maxMs)
        })

        Box(
            modifier = Modifier
                .offset(x = with(density) { segmentStartPx.toDp() })
                .width(with(density) { (segmentEndPx - segmentStartPx).coerceAtLeast(1f).toDp() })
                .fillMaxHeight()
                .clip(RoundedCornerShape(AdGagRadius.sm.dp))
                .background(AdGagColors.BrandDeep.copy(alpha = 0.55f))
                .pointerInput(Unit) {
                    detectDragGestures(
                        onDragEnd = { commit() },
                        onDrag = { change, dragAmount ->
                            change.consume()
                            onBodyDrag(dragAmount.x)
                        },
                    )
                },
        )

        // Loop repetitions after the first play: same length, back to
        // back until the video ends — drawn fainter, not draggable (the
        // first play is the one being edited; the rest follow it).
        if (viewModel.musicLoop && localDuration > 0) {
            var repStart = localStart + localDuration
            while (repStart < totalMs) {
                val repLen = minOf(localDuration, totalMs - repStart)
                Box(
                    modifier = Modifier
                        .offset(x = with(density) { msToPx(repStart).toDp() } + 1.dp)
                        .width(with(density) { (msToPx(repLen) - 1f).coerceAtLeast(1f).toDp() })
                        .fillMaxHeight()
                        .clip(RoundedCornerShape(AdGagRadius.sm.dp))
                        .background(AdGagColors.BrandDeep.copy(alpha = 0.25f)),
                )
                repStart += localDuration
            }
        }

        // Handles on both edges, drawn over the body so they win touches
        // at the edges; the same clamped-hit-box handle as the trim row.
        TrimHandle(
            xPx = segmentStartPx,
            rowWidthPx = widthPx,
            density = density,
            onDrag = { onLeftDrag(it) },
            onDragEnd = { commit() },
        )
        TrimHandle(
            xPx = segmentEndPx,
            rowWidthPx = widthPx,
            density = density,
            onDrag = { onRightDrag(it) },
            onDragEnd = { commit() },
        )
    }
}

/** GLOBAL playback position, polled (ExoPlayer doesn't push position). Read-only — never writes back to the player. Polls while paused too, so scrubs/trims move the playhead. */
@UnstableApi
@Composable
private fun rememberGlobalPositionMs(viewModel: EditorViewModel): Long {
    var position by remember { mutableLongStateOf(0L) }
    LaunchedEffect(viewModel) {
        while (true) {
            position = viewModel.globalPositionMs()
            delay(50)
        }
    }
    return position
}

private fun formatSeconds(ms: Long): String {
    val totalSeconds = ms / 1000
    return "%d:%02d".format(totalSeconds / 60, totalSeconds % 60)
}

private const val TextRowHeightDp = 30

@Composable
private fun AddRowItemButton(contentDescription: String, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(width = AddButtonSizeDp.dp, height = TextRowHeightDp.dp)
            .clip(RoundedCornerShape(AdGagRadius.sm.dp))
            .background(AdGagColors.Surface)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(imageVector = Icons.Filled.Add, contentDescription = contentDescription, tint = AdGagColors.OnBackground, modifier = Modifier.size(18.dp))
    }
}

/** One caption or sticker as a bar on the overlay row. */
private data class OverlayBar(val id: String, val kind: String, val label: String, val startMs: Long, val endMs: Long, val color: Color)

@UnstableApi
private fun overlayBars(viewModel: EditorViewModel): List<OverlayBar> =
    viewModel.stickerLayers.map { s ->
        OverlayBar(s.id, tr("Sticker"), tr(viewModel.stickers.byId(s.stickerId)?.label ?: "Sticker"), s.startMs, s.endMs, Color(0xFFFFB300))
    } + viewModel.textLayers.map { t ->
        OverlayBar(t.id, tr("Text"), t.text.lineSequence().first(), t.startMs, t.endMs, Color(t.color))
    } + viewModel.soundLayers.mapNotNull { l ->
        viewModel.sfx.byId(l.sfxId)?.let { def ->
            OverlayBar(l.id, tr("Sound"), tr(def.label), l.startMs, l.startMs + def.durationMs, Color(0xFF8C9BFF))
        }
    }

/**
 * Captions AND stickers on the OUTPUT timeline (same width and scale as
 * the clip strip). Every one is a bar; tap one to select it (and jump there),
 * tap the selected one to edit it. The selected caption gets two handles
 * (start / end) and can be dragged by its body to move it in time. Drags
 * only move local state; the caption is updated once, on release.
 */
@UnstableApi
@Composable
private fun RowScope.TextRow(viewModel: EditorViewModel, density: Density, onEditText: (String) -> Unit) {
    BoxWithConstraints(
        modifier = Modifier
            .weight(1f)
            .height(TextRowHeightDp.dp)
            .clip(RoundedCornerShape(AdGagRadius.sm.dp))
            .background(AdGagColors.Surface),
    ) {
        val widthPx = with(density) { maxWidth.toPx() }
        val total = viewModel.outputDurationMs.coerceAtLeast(1L)
        fun msToPx(ms: Long): Float = ms.toFloat() / total * widthPx
        fun pxDeltaToMsDelta(deltaPx: Float): Long = (deltaPx / widthPx * total).toLong()
        val selectedId = viewModel.selectedTextId
        val bars = overlayBars(viewModel)

        bars.filter { it.id != selectedId }.forEach { layer ->
            val left = msToPx(layer.startMs.coerceIn(0L, total))
            val right = msToPx(layer.endMs.coerceIn(0L, total)).coerceAtLeast(left + 4f)
            Box(
                modifier = Modifier
                    .offset(x = with(density) { left.toDp() })
                    .width(with(density) { (right - left).toDp() })
                    .fillMaxHeight()
                    .padding(vertical = 5.dp)
                    .clip(RoundedCornerShape(AdGagRadius.sm.dp))
                    .background(layer.color.copy(alpha = 0.35f))
                    .border(BorderStroke(1.dp, AdGagColors.Border), RoundedCornerShape(AdGagRadius.sm.dp))
                    .clickable {
                        viewModel.selectedTextId = layer.id
                        viewModel.seekToGlobal(viewModel.toSourceMs(layer.startMs))
                    },
            )
        }

        val sel = bars.firstOrNull { it.id == selectedId } ?: return@BoxWithConstraints
        var localStart by remember(sel.id, sel.startMs) { mutableLongStateOf(sel.startMs) }
        var localEnd by remember(sel.id, sel.endMs) { mutableLongStateOf(sel.endMs) }
        val commit by rememberUpdatedState({ viewModel.setOverlayTiming(sel.id, localStart, localEnd) })
        val startPx = msToPx(localStart.coerceIn(0L, total))
        val endPx = msToPx(localEnd.coerceIn(0L, total)).coerceAtLeast(startPx + 4f)
        Box(
            modifier = Modifier
                .offset(x = with(density) { startPx.toDp() })
                .width(with(density) { (endPx - startPx).toDp() })
                .fillMaxHeight()
                .padding(vertical = 3.dp)
                .clip(RoundedCornerShape(AdGagRadius.sm.dp))
                .background(AdGagColors.Accent.copy(alpha = 0.45f))
                .border(BorderStroke(2.dp, AdGagColors.Accent), RoundedCornerShape(AdGagRadius.sm.dp))
                .pointerInput(sel.id) { detectTapGestures { onEditText(sel.id) } }
                // Keyed on the committed timing too: the drag reads localStart/
                // localEnd, which are NEW state objects after every commit
                // (remember(sel.id, sel.startMs)); a block keyed on the id only
                // kept writing to the first drag's dead state, so the caption
                // could be moved once and then never again (user report).
                .pointerInput(sel.id, sel.startMs, sel.endMs, total) {
                    detectDragGestures(
                        onDragEnd = { commit() },
                        onDrag = { change, drag ->
                            change.consume()
                            val len = localEnd - localStart
                            val newStart = (localStart + pxDeltaToMsDelta(drag.x)).coerceIn(0L, (total - len).coerceAtLeast(0L))
                            localStart = newStart
                            localEnd = newStart + len
                        },
                    )
                },
            contentAlignment = Alignment.CenterStart,
        ) {
            Text(
                text = sel.label,
                color = Color.White,
                style = MaterialTheme.typography.labelSmall,
                maxLines = 1,
                modifier = Modifier.padding(horizontal = 18.dp),
            )
        }
        TrimHandle(
            xPx = startPx,
            rowWidthPx = widthPx,
            density = density,
            onDrag = { deltaPx ->
                localStart = (localStart + pxDeltaToMsDelta(deltaPx)).coerceIn(0L, (localEnd - 300L).coerceAtLeast(0L))
            },
            onDragEnd = { commit() },
        )
        TrimHandle(
            xPx = endPx,
            rowWidthPx = widthPx,
            density = density,
            onDrag = { deltaPx ->
                localEnd = (localEnd + pxDeltaToMsDelta(deltaPx)).coerceIn(localStart + 300L, total)
            },
            onDragEnd = { commit() },
        )
    }
}

private const val SpeedRowHeightDp = 30

/**
 * Slow-motion ranges on the SOURCE timeline (the clip strip's scale). Tap
 * a range to select it (and jump there), tap the selected one for its
 * settings. The selected range has two handles (start / end) and can be
 * dragged by its body. Drags only move local state, clamped live to the
 * neighbouring ranges and the 30s cap; the range is committed once, on
 * release (that rebuilds the preview).
 */
@UnstableApi
@Composable
private fun RowScope.SpeedRow(
    viewModel: EditorViewModel,
    density: Density,
    globalPositionMs: Long,
    onEditSpeedRange: (String) -> Unit,
) {
    BoxWithConstraints(
        modifier = Modifier
            .weight(1f)
            .height(SpeedRowHeightDp.dp)
            .clip(RoundedCornerShape(AdGagRadius.sm.dp))
            .background(AdGagColors.Surface),
    ) {
        val widthPx = with(density) { maxWidth.toPx() }
        val total = viewModel.totalDurationMs.coerceAtLeast(1L)
        fun msToPx(ms: Long): Float = ms.toFloat() / total * widthPx
        fun pxDeltaToMsDelta(deltaPx: Float): Long = (deltaPx / widthPx * total).toLong()
        val selectedId = viewModel.selectedSpeedRangeId

        viewModel.speedRanges.filter { it.id != selectedId }.forEach { range ->
            val left = msToPx(range.startMs)
            val right = msToPx(range.endMs).coerceAtLeast(left + 4f)
            Box(
                modifier = Modifier
                    .offset(x = with(density) { left.toDp() })
                    .width(with(density) { (right - left).toDp() })
                    .fillMaxHeight()
                    .padding(vertical = 5.dp)
                    .clip(RoundedCornerShape(AdGagRadius.sm.dp))
                    .background(AdGagColors.BrandOcean.copy(alpha = 0.45f))
                    .clickable {
                        viewModel.selectedSpeedRangeId = range.id
                        viewModel.seekToGlobal(range.startMs)
                    },
                contentAlignment = Alignment.Center,
            ) {
                Text(text = formatSpeed(range.speed), color = Color.White, style = MaterialTheme.typography.labelSmall, maxLines = 1)
            }
        }

        // Playhead (read-only), on the same SOURCE scale as the clip strip.
        Box(
            modifier = Modifier
                .offset(x = with(density) { msToPx(globalPositionMs.coerceIn(0L, total)).toDp() } - 1.dp)
                .width(2.dp)
                .fillMaxHeight()
                .background(Color.White.copy(alpha = 0.6f)),
        )

        val sel = viewModel.speedRanges.firstOrNull { it.id == selectedId } ?: return@BoxWithConstraints
        var localStart by remember(sel.id, sel.startMs) { mutableLongStateOf(sel.startMs) }
        var localEnd by remember(sel.id, sel.endMs) { mutableLongStateOf(sel.endMs) }
        val limits = viewModel.speedRangeLimits(sel.id)
        val lower = limits.first
        val upper = limits.second
        val maxLen = viewModel.maxRangeLengthMs(sel.id, sel.speed)
        val startPx = msToPx(localStart)
        val endPx = msToPx(localEnd).coerceAtLeast(startPx + 4f)
        Box(
            modifier = Modifier
                .offset(x = with(density) { startPx.toDp() })
                .width(with(density) { (endPx - startPx).toDp() })
                .fillMaxHeight()
                .padding(vertical = 3.dp)
                .clip(RoundedCornerShape(AdGagRadius.sm.dp))
                .background(AdGagColors.BrandOcean.copy(alpha = 0.7f))
                .border(BorderStroke(2.dp, AdGagColors.Accent), RoundedCornerShape(AdGagRadius.sm.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Text(text = formatSpeed(sel.speed), color = Color.White, style = MaterialTheme.typography.labelSmall, maxLines = 1)
        }
        HandleBar(xPx = startPx, rowWidthPx = widthPx, density = density)
        HandleBar(xPx = endPx, rowWidthPx = widthPx, density = density)

        // ONE gesture layer over the selected range, like the trim row: a drag
        // grabs the start edge, the end edge or (in the middle) the whole
        // range depending on where it starts — a narrow range's separate
        // handle hit boxes used to cover each other and its middle.
        val zonePx = with(density) { EdgeZoneDp.dp.toPx() }
        val startDrag by rememberUpdatedState({ x: Float -> pickDragTarget(x, msToPx(localStart), msToPx(localEnd), zonePx, bodyMoves = true) })
        val drag by rememberUpdatedState({ target: DragTarget, deltaPx: Float ->
            val d = pxDeltaToMsDelta(deltaPx)
            when (target) {
                DragTarget.START -> {
                    val min = maxOf(lower, localEnd - maxLen)
                    localStart = (localStart + d).coerceIn(min, (localEnd - MinSpeedRangeMs).coerceAtLeast(min))
                }
                DragTarget.END -> {
                    val max = minOf(upper, localStart + maxLen)
                    localEnd = (localEnd + d).coerceIn((localStart + MinSpeedRangeMs).coerceAtMost(max), max)
                }
                DragTarget.BODY -> {
                    val len = localEnd - localStart
                    val newStart = (localStart + d).coerceIn(lower, (upper - len).coerceAtLeast(lower))
                    localStart = newStart
                    localEnd = newStart + len
                }
                DragTarget.NONE -> Unit
            }
        })
        val endDrag by rememberUpdatedState({ target: DragTarget ->
            if (target != DragTarget.NONE) {
                viewModel.setSpeedRangeBounds(sel.id, localStart, localEnd, movedStart = target != DragTarget.END)
            }
        })
        val tap by rememberUpdatedState({ x: Float ->
            val sPx = msToPx(localStart)
            val ePx = msToPx(localEnd)
            if (x >= sPx - zonePx / 2 && x <= ePx + zonePx / 2) {
                onEditSpeedRange(sel.id)
            } else {
                // Another range under the finger? Select it; else just seek.
                val g = (x / widthPx * total).toLong()
                val other = viewModel.speedRanges.firstOrNull { g >= it.startMs && g < it.endMs }
                if (other != null) viewModel.selectedSpeedRangeId = other.id
                viewModel.seekToGlobal(g.coerceIn(0L, total))
            }
        })
        Box(
            modifier = Modifier
                .fillMaxSize()
                .pointerInput(Unit) {
                    var target = DragTarget.NONE
                    detectDragGestures(
                        onDragStart = { offset -> target = startDrag(offset.x) },
                        onDragEnd = { endDrag(target) },
                        onDragCancel = { endDrag(target) },
                        onDrag = { change, amount ->
                            if (target != DragTarget.NONE) change.consume()
                            drag(target, amount.x)
                        },
                    )
                }
                .pointerInput(Unit) { detectTapGestures { offset -> tap(offset.x) } },
        )
    }
}
