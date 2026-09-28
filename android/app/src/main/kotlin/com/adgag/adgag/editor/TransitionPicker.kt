package com.adgag.adgag.editor

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.media3.common.util.UnstableApi

/**
 * Bottom sheet for one clip boundary: every transition as an animated
 * mini illustration in a horizontally scrolling row, plus a duration
 * slider. Stays open while choosing so type and duration can be tuned
 * together; each change replays the boundary in the preview.
 */
@UnstableApi
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TransitionPickerSheet(viewModel: EditorViewModel, boundary: Int, onDismiss: () -> Unit) {
    val spec = viewModel.transitions.getOrNull(boundary) ?: return
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = AdGagColors.SurfaceElevated,
    ) {
        Column(modifier = Modifier.padding(bottom = AdGagSpacing.xl.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = AdGagSpacing.lg.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Clip ${boundary + 1} → Clip ${boundary + 2}",
                    color = AdGagColors.OnBackground,
                    style = MaterialTheme.typography.titleMedium,
                )
                TextButton(onClick = onDismiss) {
                    Text(text = "Done", color = AdGagColors.Accent, style = MaterialTheme.typography.labelLarge)
                }
            }
            Spacer(modifier = Modifier.height(AdGagSpacing.sm.dp))

            LazyRow(
                contentPadding = PaddingValues(horizontal = AdGagSpacing.lg.dp),
                horizontalArrangement = Arrangement.spacedBy(AdGagSpacing.md.dp),
            ) {
                items(ClipTransition.entries) { type ->
                    TransitionCard(
                        type = type,
                        selected = type == spec.type,
                        onClick = { viewModel.setTransitionType(boundary, type) },
                    )
                }
            }

            Spacer(modifier = Modifier.height(AdGagSpacing.lg.dp))
            val enabled = spec.type != ClipTransition.NONE
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = AdGagSpacing.lg.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(text = "Duration", color = AdGagColors.OnSurfaceMuted, style = MaterialTheme.typography.labelMedium)
                Text(
                    text = if (enabled) "%.1fs".format(spec.durationMs / 1000f) else "—",
                    color = AdGagColors.OnBackground,
                    style = MaterialTheme.typography.labelMedium,
                )
            }
            Slider(
                value = spec.durationMs.toFloat(),
                onValueChange = { viewModel.setTransitionDuration(boundary, it.toLong()) },
                onValueChangeFinished = { viewModel.replayTransition(boundary) },
                valueRange = MinTransitionDurationMs.toFloat()..MaxTransitionDurationMs.toFloat(),
                // 0.1s steps between 0.2s and 2.0s.
                steps = ((MaxTransitionDurationMs - MinTransitionDurationMs) / 100 - 1).toInt(),
                enabled = enabled,
                colors = SliderDefaults.colors(
                    thumbColor = AdGagColors.Accent,
                    activeTrackColor = AdGagColors.Accent,
                ),
                modifier = Modifier.padding(horizontal = AdGagSpacing.lg.dp),
            )
        }
    }
}

private const val DemoClipMs = 1_400L
private const val DemoTransitionMs = 800L

/**
 * A card whose picture is a tiny looping animation of the effect (the
 * outgoing then the incoming side, both drawn as the pink frame), posed by the
 * SAME [TransitionMath.clipPose] the real preview and export use — so the
 * thumbnail can't drift from what the effect actually does.
 */
@Composable
private fun TransitionCard(type: ClipTransition, selected: Boolean, onClick: () -> Unit) {
    val loop = rememberInfiniteTransition(label = "transition-demo")
    val t by loop.animateFloat(
        initialValue = 0f,
        targetValue = (DemoClipMs * 2).toFloat(),
        animationSpec = infiniteRepeatable(tween((DemoClipMs * 2).toInt(), easing = LinearEasing), RepeatMode.Restart),
        label = "transition-demo-time",
    )
    val spec = TransitionSpec(type, DemoTransitionMs)

    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(72.dp)) {
        Box(
            modifier = Modifier
                .size(width = 64.dp, height = 96.dp)
                .clip(RoundedCornerShape(AdGagRadius.sm.dp))
                .border(
                    BorderStroke(if (selected) 2.dp else 1.dp, if (selected) AdGagColors.Accent else AdGagColors.Border),
                    RoundedCornerShape(AdGagRadius.sm.dp),
                )
                .background(Color.Black)
                .clipToBounds()
                .clickable(onClick = onClick),
        ) {
            Canvas(modifier = Modifier.size(width = 64.dp, height = 96.dp)) {
                val time = t.toLong()
                val isA = time < DemoClipMs
                val local = if (isA) time else time - DemoClipMs
                val pose = if (isA) {
                    TransitionMath.clipPose(entry = null, exit = spec, keptMs = DemoClipMs, localMs = local)
                } else {
                    TransitionMath.clipPose(entry = spec, exit = null, keptMs = DemoClipMs, localMs = local)
                }
                drawPosedFrame(pose)
            }
        }
        Spacer(modifier = Modifier.height(AdGagSpacing.xs.dp))
        Text(
            text = type.label,
            color = if (selected) AdGagColors.Accent else AdGagColors.OnSurfaceMuted,
            style = MaterialTheme.typography.labelSmall,
            textAlign = TextAlign.Center,
            maxLines = 1,
        )
    }
}

/**
 * One mini "video frame" (pink with a mountain) drawn at [pose], then a
 * black veil for its brightness. Both sides of the transition use the same
 * pink frame — by request, only the pink illustration moves.
 */
private fun DrawScope.drawPosedFrame(pose: TransitionMath.Pose) {
    val w = size.width
    val h = size.height
    translate(left = pose.translateX * w, top = pose.translateY * h) {
        rotate(degrees = pose.rotationDegrees, pivot = center) {
            scale(scale = pose.scale, pivot = center) {
                drawRect(AdGagColors.Accent)
                val mountain = Path().apply {
                    moveTo(w * 0.05f, h * 0.78f)
                    lineTo(w * 0.40f, h * 0.36f)
                    lineTo(w * 0.62f, h * 0.60f)
                    lineTo(w * 0.75f, h * 0.48f)
                    lineTo(w * 0.95f, h * 0.78f)
                    close()
                }
                drawPath(mountain, Color.White.copy(alpha = 0.9f))
                drawCircle(Color.White.copy(alpha = 0.9f), radius = w * 0.1f, center = Offset(w * 0.72f, h * 0.24f))
            }
        }
    }
    if (pose.brightness < 1f) drawRect(Color.Black.copy(alpha = 1f - pose.brightness))
}
