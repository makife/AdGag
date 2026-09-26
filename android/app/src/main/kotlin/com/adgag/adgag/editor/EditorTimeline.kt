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
    modifier: Modifier = Modifier,
) {
    val density = LocalDensity.current
    val positionMs = rememberGlobalPositionMs(viewModel)

    Column(modifier = modifier) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(text = "Clips", color = AdGagColors.OnSurfaceMuted, style = MaterialTheme.typography.labelMedium)
            Text(
                text = "${formatSeconds(viewModel.totalDurationMs)} / ${formatSeconds(MaxTotalDurationMs)}",
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
                    text = if (viewModel.clips.size > 1) "Clip ${selected + 1} · trim" else "Trim",
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
                            text = "Delete clip",
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

        if (viewModel.musicPath != null && viewModel.musicDurationMs != null) {
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
            AlignedRow(trailing = null) { MusicRow(viewModel, density) }
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
private fun AddClipButton(enabled: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(AddButtonSizeDp.dp)
            .clip(RoundedCornerShape(AdGagRadius.sm.dp))
            .background(if (enabled) AdGagColors.GradientPink else AdGagColors.Border)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(imageVector = Icons.Filled.Add, contentDescription = "Record another clip", tint = AdGagColors.OnBackground)
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
                                    Modifier.border(BorderStroke(2.dp, AdGagColors.GradientPink), RoundedCornerShape(AdGagRadius.sm.dp))
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
                    .background(if (active) AdGagColors.GradientPink else AdGagColors.SurfaceElevated)
                    .border(BorderStroke(1.dp, AdGagColors.OnBackground.copy(alpha = 0.6f)), CircleShape)
                    .clickable { onPickTransition(b) },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.AutoAwesome,
                    contentDescription = "Transition effect",
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
        val maxKeptMs = (MaxTotalDurationMs - (viewModel.totalDurationMs - clip.keptDurationMs)).coerceAtLeast(MinTrimGapMs)

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
        Box(
            modifier = Modifier
                .fillMaxSize()
                .pointerInput(Unit) {
                    detectDragGestures { change, _ ->
                        change.consume()
                        scrub(change.position.x)
                    }
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

        TrimHandle(
            xPx = startPx,
            rowWidthPx = widthPx,
            density = density,
            onDrag = { deltaPx ->
                val lower = (localEnd - maxKeptMs).coerceAtLeast(0L)
                val upper = (localEnd - MinTrimGapMs).coerceAtLeast(lower)
                localStart = (localStart + pxDeltaToMsDelta(deltaPx)).coerceIn(lower, upper)
            },
            onDragEnd = { viewModel.setClipTrim(index, localStart, localEnd) },
        )
        TrimHandle(
            xPx = endPx,
            rowWidthPx = widthPx,
            density = density,
            onDrag = { deltaPx ->
                val lower = localStart + MinTrimGapMs
                val upper = minOf(sourceMs, localStart + maxKeptMs).coerceAtLeast(lower)
                localEnd = (localEnd + pxDeltaToMsDelta(deltaPx)).coerceIn(lower, upper)
            },
            onDragEnd = { viewModel.setClipTrim(index, localStart, localEnd) },
        )
    }
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
                .background(AdGagColors.GradientPink),
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
        val totalMs = viewModel.totalDurationMs.coerceAtLeast(1L)
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
                .background(AdGagColors.GradientBlue.copy(alpha = 0.55f))
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
