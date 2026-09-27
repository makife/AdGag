package com.adgag.adgag.editor

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.media3.common.util.UnstableApi

/** Music settings: speed, fade in/out, replace, remove. */
@UnstableApi
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MusicSheet(viewModel: EditorViewModel, onReplace: () -> Unit, onDismiss: () -> Unit) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = AdGagColors.SurfaceElevated,
    ) {
        Column(modifier = Modifier.padding(bottom = AdGagSpacing.xl.dp)) {
            SheetHeader(title = "Music", onDone = onDismiss)

            SectionLabel("Speed")
            ChoiceRow(
                options = MusicSpeedOptions,
                selected = viewModel.musicSpeed,
                enabled = { !viewModel.isAttachingMusic },
                label = { formatSpeed(it) },
                onSelect = { viewModel.changeMusicSpeed(it) },
            )
            if (viewModel.isAttachingMusic) {
                PreparingMusicIndicator(modifier = Modifier.padding(horizontal = AdGagSpacing.lg.dp, vertical = AdGagSpacing.xs.dp))
            }

            Spacer(modifier = Modifier.height(AdGagSpacing.sm.dp))
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { viewModel.changeMusicLoop(!viewModel.musicLoop) }
                    .padding(horizontal = AdGagSpacing.lg.dp, vertical = AdGagSpacing.xs.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(text = "Loop to fill the video", color = AdGagColors.OnBackground, style = MaterialTheme.typography.bodyMedium)
                    Text(
                        text = "Repeats the selected part until the video ends",
                        color = AdGagColors.OnSurfaceMuted,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                Switch(
                    checked = viewModel.musicLoop,
                    onCheckedChange = { viewModel.changeMusicLoop(it) },
                    colors = SwitchDefaults.colors(checkedTrackColor = AdGagColors.GradientPink),
                )
            }

            val maxFade = minOf(MaxMusicFadeMs, viewModel.musicCoveredMs).coerceAtLeast(0L)
            FadeSlider(
                label = "Fade in",
                valueMs = viewModel.musicFadeInMs,
                maxMs = maxFade,
                onChange = { viewModel.setMusicFade(it, viewModel.musicFadeOutMs) },
            )
            FadeSlider(
                label = "Fade out",
                valueMs = viewModel.musicFadeOutMs,
                maxMs = maxFade,
                onChange = { viewModel.setMusicFade(viewModel.musicFadeInMs, it) },
            )

            Spacer(modifier = Modifier.height(AdGagSpacing.md.dp))
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = AdGagSpacing.lg.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                TextButton(onClick = onReplace) {
                    Text(text = "Replace music", color = AdGagColors.OnBackground, style = MaterialTheme.typography.labelLarge)
                }
                TextButton(onClick = {
                    viewModel.removeMusic()
                    onDismiss()
                }) {
                    Text(text = "Remove music", color = AdGagColors.Danger, style = MaterialTheme.typography.labelLarge)
                }
            }
        }
    }
}

/** Whole-video speed (slow motion). Speeds that would push the Ad past 30s are disabled, with the reason shown. */
@UnstableApi
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VideoSpeedSheet(viewModel: EditorViewModel, onDismiss: () -> Unit) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = AdGagColors.SurfaceElevated,
    ) {
        Column(modifier = Modifier.padding(bottom = AdGagSpacing.xl.dp)) {
            SheetHeader(title = "Video speed", onDone = onDismiss)
            ChoiceRow(
                options = VideoSpeedOptions,
                selected = viewModel.videoSpeed,
                enabled = { viewModel.canUseVideoSpeed(it) },
                label = { formatSpeed(it) },
                onSelect = { viewModel.changeVideoSpeed(it) },
            )
            Spacer(modifier = Modifier.height(AdGagSpacing.sm.dp))
            val blocked = VideoSpeedOptions.filterNot { viewModel.canUseVideoSpeed(it) }
            Text(
                text = if (blocked.isEmpty()) {
                    "Slow motion stretches the whole Ad. Your Ad: ${formatClock(viewModel.outputDurationMs)}."
                } else {
                    "${blocked.joinToString { formatSpeed(it) }} would make the Ad longer than 30s — trim it first."
                },
                color = AdGagColors.OnSurfaceMuted,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(horizontal = AdGagSpacing.lg.dp),
            )
        }
    }
}

/** "Preparing music…" with a thin indeterminate progress line under it — re-timing a song takes a few seconds. */
@Composable
fun PreparingMusicIndicator(modifier: Modifier = Modifier) {
    Column(modifier = modifier.fillMaxWidth()) {
        Text(text = "Preparing music…", color = AdGagColors.OnSurfaceMuted, style = MaterialTheme.typography.bodySmall)
        Spacer(modifier = Modifier.height(AdGagSpacing.xs.dp))
        LinearProgressIndicator(
            modifier = Modifier.fillMaxWidth().height(2.dp),
            color = AdGagColors.GradientPink,
            trackColor = AdGagColors.Border,
        )
    }
}

@Composable
private fun SheetHeader(title: String, onDone: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = AdGagSpacing.lg.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text = title, color = AdGagColors.OnBackground, style = MaterialTheme.typography.titleMedium)
        TextButton(onClick = onDone) {
            Text(text = "Done", color = AdGagColors.GradientPink, style = MaterialTheme.typography.labelLarge)
        }
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(
        text = text,
        color = AdGagColors.OnSurfaceMuted,
        style = MaterialTheme.typography.labelMedium,
        modifier = Modifier.padding(horizontal = AdGagSpacing.lg.dp, vertical = AdGagSpacing.xs.dp),
    )
}

@Composable
private fun ChoiceRow(
    options: List<Float>,
    selected: Float,
    enabled: (Float) -> Boolean,
    label: (Float) -> String,
    onSelect: (Float) -> Unit,
) {
    LazyRow(
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = AdGagSpacing.lg.dp),
        horizontalArrangement = Arrangement.spacedBy(AdGagSpacing.sm.dp),
    ) {
        items(options) { option ->
            val isSelected = option == selected
            val isEnabled = enabled(option)
            Text(
                text = label(option),
                color = AdGagColors.OnBackground,
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier
                    .alpha(if (isEnabled || isSelected) 1f else 0.35f)
                    .clip(RoundedCornerShape(AdGagRadius.pill.dp))
                    .background(if (isSelected) AdGagColors.GradientPink else AdGagColors.Surface)
                    .clickable(enabled = isEnabled && !isSelected) { onSelect(option) }
                    .padding(horizontal = AdGagSpacing.lg.dp, vertical = AdGagSpacing.sm.dp),
            )
        }
    }
}

@Composable
private fun FadeSlider(label: String, valueMs: Long, maxMs: Long, onChange: (Long) -> Unit) {
    Spacer(modifier = Modifier.height(AdGagSpacing.sm.dp))
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = AdGagSpacing.lg.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(text = label, color = AdGagColors.OnSurfaceMuted, style = MaterialTheme.typography.labelMedium)
        Text(
            text = if (valueMs == 0L) "Off" else "%.1fs".format(valueMs / 1000f),
            color = AdGagColors.OnBackground,
            style = MaterialTheme.typography.labelMedium,
        )
    }
    Slider(
        value = valueMs.toFloat().coerceIn(0f, maxMs.toFloat().coerceAtLeast(1f)),
        onValueChange = { onChange((it / 100).toLong() * 100) }, // 0.1s steps
        valueRange = 0f..maxMs.toFloat().coerceAtLeast(1f),
        enabled = maxMs > 0,
        colors = SliderDefaults.colors(thumbColor = AdGagColors.GradientPink, activeTrackColor = AdGagColors.GradientPink),
        modifier = Modifier.padding(horizontal = AdGagSpacing.lg.dp),
    )
}

/** 1f -> "1x", 0.25f -> "0.25x". */
fun formatSpeed(speed: Float): String =
    if (speed == speed.toInt().toFloat()) "${speed.toInt()}x" else "${speed}x"

fun formatClock(ms: Long): String {
    val totalSeconds = ms / 1000
    return "%d:%02d".format(totalSeconds / 60, totalSeconds % 60)
}
