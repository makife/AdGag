package com.adgag.adgag.editor

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.MusicOff
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.RotateRight
import androidx.compose.material.icons.filled.VolumeOff
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RangeSlider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.compose.PlayerSurface
import androidx.media3.ui.compose.SURFACE_TYPE_SURFACE_VIEW

/**
 * The native editor's screen, phase 1 feature set (preview, trim, one
 * background-music attachment, rotate, mute) presented in AdGag's own
 * visual language — [AdGagColors]/[AdGagSpacing]/[AdGagRadius], hand-
 * mirrored from the Flutter app's design system (see that file's own
 * doc comment). Full-bleed video, restrained dark overlays, the brand
 * gradient used sparingly on the one primary action (Next) — matching
 * CLAUDE.md section 35's "video must dominate... overlays visually
 * restrained... avoid excessive gradients" directly, not just in name.
 */
@UnstableApi
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditorScreen(
    viewModel: EditorViewModel,
    onCancel: () -> Unit,
    onExported: (path: String, durationMs: Long) -> Unit,
    exportOutputPath: String,
) {
    AdGagEditorTheme {
        val pickMusic = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
            if (uri != null) viewModel.setMusic(uri)
        }

        Box(modifier = Modifier.fillMaxSize().background(AdGagColors.Background)) {
            // Full-bleed video — the dominant visual element, per this
            // app's own standing rule everywhere else in the product.
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                PlayerSurface(player = viewModel.player, surfaceType = SURFACE_TYPE_SURFACE_VIEW)
            }

            // Center play/pause — only shown while paused, so it never
            // competes with the content while actually playing (an
            // always-visible control here would be exactly the kind of
            // "cheap meme app" clutter section 35 warns against).
            AnimatedVisibility(
                visible = !viewModel.isPlaying,
                modifier = Modifier.align(Alignment.Center),
                enter = fadeIn(),
                exit = fadeOut(),
            ) {
                ScrimIconButton(
                    icon = Icons.Filled.PlayArrow,
                    contentDescription = "Play",
                    size = 64.dp,
                    onClick = { viewModel.togglePlayPause() },
                )
            }

            // Top bar: transparent over video, Cancel + a branded-
            // gradient Next pill — the one place this screen uses the
            // brand gradient, matching "used sparingly as an accent."
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .windowInsetsPadding(WindowInsets.systemBars)
                    .padding(horizontal = AdGagSpacing.lg.dp, vertical = AdGagSpacing.sm.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                ScrimIconButton(
                    icon = null,
                    text = "Cancel",
                    contentDescription = "Cancel",
                    onClick = onCancel,
                )
                NextButton(
                    enabled = !viewModel.isExporting,
                    onClick = {
                        viewModel.export(
                            outputPath = exportOutputPath,
                            onProgress = {},
                            onComplete = { path, _ ->
                                if (path != null) {
                                    onExported(path, viewModel.trimEndMs - viewModel.trimStartMs)
                                }
                                // A non-null error is already surfaced via
                                // viewModel.exportError, rendered below —
                                // the screen stays open so it's visible,
                                // matching this app's "never silently
                                // fail" rule.
                            },
                        )
                    },
                )
            }

            // Bottom control panel: a rounded, elevated dark sheet —
            // exactly the "restrained overlay" treatment the rest of
            // AdGag's video surfaces already use, not a redesign of the
            // whole screen's visual language, just this screen's own
            // application of it.
            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(topStart = AdGagRadius.lg.dp, topEnd = AdGagRadius.lg.dp))
                    .background(AdGagColors.SurfaceElevated)
                    .windowInsetsPadding(WindowInsets.systemBars)
                    .padding(horizontal = AdGagSpacing.lg.dp, vertical = AdGagSpacing.lg.dp),
            ) {
                if (viewModel.durationMs > 0) {
                    TimelineSection(viewModel)
                    Spacer(modifier = Modifier.height(AdGagSpacing.lg.dp))
                }

                ToolRow(viewModel = viewModel, onPickMusic = { pickMusic.launch("audio/*") })

                if (viewModel.isExporting) {
                    Spacer(modifier = Modifier.height(AdGagSpacing.md.dp))
                    ExportProgress(viewModel.exportProgress)
                }
                val error = viewModel.exportError
                if (error != null) {
                    Spacer(modifier = Modifier.height(AdGagSpacing.sm.dp))
                    Text(
                        text = "Export failed: $error",
                        color = AdGagColors.Danger,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }
        }
    }
}

/**
 * Real user report: "eklediğim müziği timelineda göremiyorum, timeline
 * yapmamışsın" (can't see the music I added in a timeline, you didn't
 * build one) — the previous version was just a trim slider with no
 * visual track at all. This is a real, if minimal, two-row timeline: a
 * Clip row (the trim slider itself, functionally unchanged — already
 * proven to work) and a Music row directly beneath it, drawn to scale
 * against the SAME ruler, showing exactly where the attached music
 * plays relative to the clip. Music always starts at the trim window's
 * own start (this phase's `EditorViewModel` has no per-track start-
 * offset concept yet — matches the actual composition logic, not an
 * idealized picture of it) and runs for its own real probed duration,
 * clamped to the trim window's end.
 */
@Composable
private fun TimelineSection(viewModel: EditorViewModel) {
    Column {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(text = "Clip", color = AdGagColors.OnSurfaceMuted, style = MaterialTheme.typography.labelMedium)
            Text(
                text = "${formatSeconds(viewModel.trimStartMs)} – ${formatSeconds(viewModel.trimEndMs)}",
                color = AdGagColors.OnSurfaceMuted,
                style = MaterialTheme.typography.labelMedium,
            )
        }
        Spacer(modifier = Modifier.height(AdGagSpacing.xs.dp))
        // The plain value/onValueChange/valueRange overload — proven to
        // compile against this project's pinned Compose BOM (2026.06.01)
        // earlier this session; the newer state-hoisting RangeSliderState
        // API's availability at that exact BOM wasn't verified, so this
        // is the safer, confirmed choice, not a downgrade.
        RangeSlider(
            value = viewModel.trimStartMs.toFloat()..viewModel.trimEndMs.toFloat(),
            valueRange = 0f..viewModel.durationMs.toFloat(),
            onValueChange = { range ->
                viewModel.setTrim(range.start.toLong(), range.endInclusive.toLong())
            },
            colors = SliderDefaults.colors(
                activeTrackColor = AdGagColors.GradientPink,
                inactiveTrackColor = AdGagColors.Border,
                thumbColor = Color.White,
            ),
        )

        val musicDurationMs = viewModel.musicDurationMs
        if (viewModel.musicUri != null && musicDurationMs != null && viewModel.durationMs > 0) {
            Spacer(modifier = Modifier.height(AdGagSpacing.xs.dp))
            Text(text = "Music", color = AdGagColors.OnSurfaceMuted, style = MaterialTheme.typography.labelMedium)
            Spacer(modifier = Modifier.height(AdGagSpacing.xs.dp))
            val totalMs = viewModel.durationMs.toFloat()
            val segmentStartFraction = (viewModel.trimStartMs / totalMs).coerceIn(0f, 1f)
            val segmentEndMs = (viewModel.trimStartMs + musicDurationMs).coerceAtMost(viewModel.trimEndMs)
            val segmentEndFraction = (segmentEndMs / totalMs).coerceIn(segmentStartFraction, 1f)
            BoxWithConstraints(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(20.dp)
                    .clip(RoundedCornerShape(AdGagRadius.sm.dp))
                    .background(AdGagColors.Surface),
            ) {
                val trackWidth = maxWidth
                Box(
                    modifier = Modifier
                        .offset(x = trackWidth * segmentStartFraction)
                        .width(trackWidth * (segmentEndFraction - segmentStartFraction))
                        .fillMaxSize()
                        .clip(RoundedCornerShape(AdGagRadius.sm.dp))
                        .background(AdGagColors.GradientBlue.copy(alpha = 0.55f)),
                )
            }
        }
    }
}

private fun formatSeconds(ms: Long): String {
    val totalSeconds = ms / 1000
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "%d:%02d".format(minutes, seconds)
}

@Composable
private fun ToolRow(viewModel: EditorViewModel, onPickMusic: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(AdGagSpacing.lg.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        EditorToolButton(
            icon = Icons.Filled.RotateRight,
            label = "Rotate",
            onClick = { viewModel.rotateNinety() },
        )
        EditorToolButton(
            icon = if (viewModel.isMuted) Icons.Filled.VolumeOff else Icons.Filled.VolumeUp,
            label = if (viewModel.isMuted) "Muted" else "Mute",
            active = viewModel.isMuted,
            onClick = { viewModel.toggleMute() },
        )
        EditorToolButton(
            icon = if (viewModel.musicUri != null) Icons.Filled.MusicNote else Icons.Filled.MusicOff,
            label = if (viewModel.musicUri != null) "Music added" else "Add music",
            active = viewModel.musicUri != null,
            onClick = onPickMusic,
        )
    }
}

/** Icon-in-a-circle tool button — the same visual language `ActionRailIcon` already establishes on the Flutter feed screen (a small dark circle behind each action icon), reused here for consistency across the app, not reinvented. */
@Composable
private fun EditorToolButton(
    icon: ImageVector,
    label: String,
    active: Boolean = false,
    onClick: () -> Unit,
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            modifier = Modifier
                .size(48.dp)
                .clip(CircleShape)
                .background(if (active) AdGagColors.GradientPink.copy(alpha = 0.25f) else AdGagColors.Surface),
            contentAlignment = Alignment.Center,
        ) {
            IconButton(onClick = onClick) {
                Icon(
                    imageVector = icon,
                    contentDescription = label,
                    tint = if (active) AdGagColors.GradientPink else AdGagColors.OnBackground,
                )
            }
        }
        Spacer(modifier = Modifier.height(AdGagSpacing.xs.dp))
        Text(text = label, color = AdGagColors.OnSurfaceMuted, style = MaterialTheme.typography.labelSmall)
    }
}

/** A small translucent-black circular scrim behind an icon/text — legible over any video frame without a heavy opaque background. */
@Composable
private fun ScrimIconButton(
    icon: ImageVector?,
    contentDescription: String,
    onClick: () -> Unit,
    text: String? = null,
    size: Dp = 40.dp,
) {
    Box(
        modifier = Modifier
            .clip(if (icon != null) CircleShape else RoundedCornerShape(AdGagRadius.pill.dp))
            .background(AdGagColors.OverlayScrim)
            .then(if (icon != null) Modifier.size(size) else Modifier),
        contentAlignment = Alignment.Center,
    ) {
        if (icon != null) {
            IconButton(onClick = onClick) {
                Icon(imageVector = icon, contentDescription = contentDescription, tint = Color.White, modifier = Modifier.size(size * 0.55f))
            }
        } else {
            // REAL BUG found via user report ("cancel button doesn't
            // work"): this branch used to be a plain Text with no click
            // handling at all — onClick was accepted as a parameter but
            // never actually wired to anything in this code path. Fixed
            // by using TextButton, the same click-handling widget
            // NextButton already uses correctly.
            TextButton(onClick = onClick) {
                Text(
                    text = text ?: contentDescription,
                    color = Color.White,
                    style = MaterialTheme.typography.labelLarge,
                )
            }
        }
    }
}

@Composable
private fun NextButton(enabled: Boolean, onClick: () -> Unit) {
    val background = if (enabled) {
        AdGagColors.BrandGradient
    } else {
        Brush.horizontalGradient(listOf(AdGagColors.Border, AdGagColors.Border))
    }
    Box(
        modifier = Modifier.clip(RoundedCornerShape(AdGagRadius.pill.dp)).background(background),
        contentAlignment = Alignment.Center,
    ) {
        TextButton(onClick = onClick, enabled = enabled) {
            Text(
                text = "Next",
                color = Color.White,
                style = MaterialTheme.typography.labelLarge,
                fontSize = 15.sp,
            )
        }
    }
}

@Composable
private fun ExportProgress(progress: Float) {
    Column {
        Text(
            text = "Exporting your Ad…",
            color = AdGagColors.OnSurfaceMuted,
            style = MaterialTheme.typography.bodyMedium,
        )
        Spacer(modifier = Modifier.height(AdGagSpacing.xs.dp))
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(6.dp)
                .clip(RoundedCornerShape(AdGagRadius.pill.dp))
                .background(AdGagColors.Border),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth(if (progress > 0f) progress.coerceIn(0f, 1f) else 1f)
                    .height(6.dp)
                    .clip(RoundedCornerShape(AdGagRadius.pill.dp))
                    .background(AdGagColors.BrandGradient),
            )
        }
    }
}
