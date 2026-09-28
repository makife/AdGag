package com.adgag.adgag.editor

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.animation.togetherWith
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.core.tween
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.AnimatedContent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoFixHigh
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.MusicOff
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.RotateRight
import androidx.compose.material.icons.filled.SlowMotionVideo
import androidx.compose.material.icons.filled.EmojiEmotions
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material.icons.filled.VolumeOff
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.compose.ContentFrame
import androidx.media3.ui.compose.SURFACE_TYPE_TEXTURE_VIEW

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
    /** The timeline's "+" — the Activity closes so Flutter's camera can record another clip. */
    onAddClip: () -> Unit,
    exportOutputPath: String,
) {
    AdGagEditorTheme {
        val pickMusic = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
            if (uri != null) viewModel.setMusic(uri)
        }
        // -1 = picker closed; otherwise the clip boundary being edited.
        var pickingTransitionFor by remember { mutableIntStateOf(-1) }
        var showMusicSheet by remember { mutableStateOf(false) }
        // The speed range whose settings sheet is open (null = closed).
        var speedSheetFor by remember { mutableStateOf<String?>(null) }
        var showEffectsSheet by remember { mutableStateOf(false) }
        var editingTextId by remember { mutableStateOf<String?>(null) }
        // The bottom panel dragged down out of the way (the video gets the space).
        var panelCollapsed by remember { mutableStateOf(false) }
        // Sticker picker: null = closed; "" = adding; otherwise the sticker being changed.
        var stickerPanelFor by remember { mutableStateOf<String?>(null) }
        // Sound FX picker: same convention.
        var soundPanelFor by remember { mutableStateOf<String?>(null) }
        val addText = {
            viewModel.player.pause()
            stickerPanelFor = null
            soundPanelFor = null
            editingTextId = viewModel.addText().id
        }
        val openStickers = {
            viewModel.player.pause()
            editingTextId = null
            soundPanelFor = null
            stickerPanelFor = ""
        }
        val openSounds = {
            viewModel.player.pause()
            editingTextId = null
            stickerPanelFor = null
            soundPanelFor = ""
        }
        // Speed tool / the Speed row's "+": a slow-motion range at the
        // playhead (or the one the playhead is in), then its settings.
        val openSpeed = {
            val range = viewModel.addSpeedRangeAtPlayhead()
            if (range != null) {
                speedSheetFor = range.id
            } else {
                viewModel.showNotice(tr("No room for slow motion — the Ad is already 30s. Trim it first."))
            }
        }
        // Tapping a selected overlay (or its timeline bar) opens the matching editor.
        val editOverlay = { id: String ->
            viewModel.player.pause()
            editingTextId = null
            stickerPanelFor = null
            soundPanelFor = null
            when {
                viewModel.stickerLayers.any { it.id == id } -> stickerPanelFor = id
                viewModel.soundLayers.any { it.id == id } -> soundPanelFor = id
                else -> editingTextId = id
            }
        }

        // Per-frame GLOBAL position, read ONLY inside the graphicsLayer /
        // drawBehind lambdas below — the entrance transitions animate
        // every frame without recomposing the screen.
        val frameGlobalMs = remember { mutableLongStateOf(0L) }
        LaunchedEffect(viewModel) {
            while (true) {
                withFrameMillis { }
                frameGlobalMs.longValue = viewModel.globalPositionMs()
                // Music fade-in/out in the preview is a per-frame volume envelope.
                viewModel.updatePreviewVolume(frameGlobalMs.longValue)
                // Sound effects fire as the playhead passes them.
                viewModel.updatePreviewSounds(frameGlobalMs.longValue)
            }
        }

        // Stacked, not overlaid: top bar, then the video (whatever height
        // is left, aspect ratio kept), then the editing panel. The panel
        // used to sit ON TOP of a full-bleed video and hid most of it
        // (user report: "you can't see what the edits change").
        Column(modifier = Modifier.fillMaxSize().background(AdGagColors.Background)) {
            // Top bar: Cancel + the branded-gradient Next pill — the one
            // place this screen uses the brand gradient.
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .windowInsetsPadding(WindowInsets.statusBars)
                    .padding(horizontal = AdGagSpacing.lg.dp, vertical = AdGagSpacing.sm.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                ScrimIconButton(
                    icon = null,
                    text = tr("Cancel"),
                    contentDescription = tr("Cancel"),
                    onClick = onCancel,
                )
                NextButton(
                    enabled = !viewModel.isExporting,
                    onClick = {
                        viewModel.export(
                            outputPath = exportOutputPath,
                            onComplete = { path, _ ->
                                if (path != null) {
                                    onExported(path, viewModel.outputDurationMs)
                                }
                                // A non-null error is surfaced via
                                // viewModel.exportError in the panel — the
                                // screen stays open so it's visible.
                            },
                        )
                    },
                )
            }

            // Video area. Rotation preview is a Compose rotation of the
            // rendered surface (plain ExoPlayer has no effects pipeline);
            // the export bakes in the real rotation. clipToBounds keeps
            // slide/zoom/spin transitions from drawing over the panels.
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    // Taps (play/pause, selecting captions) are handled by
                    // TextOverlayLayer below; the center button still wins
                    // taps inside its own bounds.
                    .clipToBounds(),
                contentAlignment = Alignment.Center,
            ) {
                // TextureView, not SurfaceView: a SurfaceView lives in its
                // own window layer and ignores most Compose transforms,
                // which the transition preview relies on. ContentFrame
                // scales the video to FIT this area with its aspect ratio
                // kept; keepContentOnReset avoids a black flash each time
                // an edit rebuilds the playlist.
                ContentFrame(
                    player = viewModel.player,
                    surfaceType = SURFACE_TYPE_TEXTURE_VIEW,
                    keepContentOnReset = true,
                    modifier = Modifier.graphicsLayer {
                        val pose = transitionPoseAt(viewModel, frameGlobalMs.longValue)
                        rotationZ = viewModel.rotationDegrees + pose.rotationDegrees
                        // Turned a quarter, the fitted picture is too big for
                        // the area (a sideways take showed cut off): shrink it
                        // so the TURNED picture fits.
                        val turn = quarterTurnFit(viewModel, size.width, size.height)
                        scaleX = pose.scale * turn
                        scaleY = pose.scale * turn
                        translationX = pose.translateX * size.width
                        translationY = pose.translateY * size.height
                    },
                )
                // Fade transitions: a black veil over the video.
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .drawBehind {
                            val b = transitionPoseAt(viewModel, frameGlobalMs.longValue).brightness
                            if (b < 1f) drawRect(Color.Black, alpha = 1f - b)
                        },
                )
                // Captions — above the video and transitions (they're
                // composition-level in the export too, so transitions
                // never move them).
                TextOverlayLayer(
                    viewModel = viewModel,
                    frameGlobalMs = frameGlobalMs,
                    onEdit = editOverlay,
                )
                // Center play button — only while paused.
                androidx.compose.animation.AnimatedVisibility(
                    visible = !viewModel.isPlaying,
                    enter = fadeIn(),
                    exit = fadeOut(),
                ) {
                    ScrimIconButton(
                        icon = Icons.Filled.PlayArrow,
                        contentDescription = tr("Play"),
                        size = 64.dp,
                        onClick = { viewModel.togglePlayPause() },
                    )
                }
            }

            // The panel under the video: the editor (timeline + tools), or the
            // text / sticker editors IN ITS PLACE — never over the video. A
            // drag handle on top collapses it (the video grows into the
            // space) and expands it again; a newly opened panel slides up.
            val panelKind = when {
                soundPanelFor != null -> PanelKind.SOUNDS
                stickerPanelFor != null -> PanelKind.STICKERS
                editingTextId != null -> PanelKind.TEXT
                else -> PanelKind.EDITOR
            }
            LaunchedEffect(panelKind) { panelCollapsed = false }
            // Back closes the text / sticker panel instead of leaving the editor.
            BackHandler(enabled = panelKind != PanelKind.EDITOR) {
                editingTextId = null
                stickerPanelFor = null
                soundPanelFor = null
            }
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(topStart = AdGagRadius.lg.dp, topEnd = AdGagRadius.lg.dp))
                    .background(AdGagColors.SurfaceElevated)
                    // The keyboard too: targetSdk 36 makes the window edge-to-edge
                    // on Android 15+, where adjustResize no longer shrinks it —
                    // the keyboard covered this panel (user report). With the
                    // ime inset here the panel sits on the keyboard and the
                    // video (weight 1f) shrinks upward instead.
                    .windowInsetsPadding(WindowInsets.navigationBars.union(WindowInsets.ime))
                    .animateContentSize(tween(260)),
            ) {
                PanelHandle(
                    collapsed = panelCollapsed,
                    label = when (panelKind) {
                        PanelKind.EDITOR -> tr("Editor")
                        PanelKind.TEXT -> tr("Text")
                        PanelKind.STICKERS -> tr("Stickers")
                        PanelKind.SOUNDS -> tr("Sound FX")
                    },
                    onCollapsedChange = { panelCollapsed = it },
                    onDone = if (panelKind == PanelKind.EDITOR) {
                        null
                    } else {
                        {
                            editingTextId = null
                            stickerPanelFor = null
                            soundPanelFor = null
                        }
                    },
                )
                if (!panelCollapsed) {
                    AnimatedContent(
                        targetState = panelKind,
                        transitionSpec = {
                            (slideInVertically(tween(300)) { it } + fadeIn(tween(200))) togetherWith
                                fadeOut(tween(120)) using SizeTransform(clip = false)
                        },
                        label = "editorPanel",
                    ) { kind ->
                        when (kind) {
                            PanelKind.SOUNDS -> Column(modifier = Modifier.padding(bottom = AdGagSpacing.sm.dp)) {
                                val editing = soundPanelFor?.ifEmpty { null }
                                SoundPanelHeader(viewModel = viewModel, editingId = editing, onDismiss = { soundPanelFor = null })
                                SoundPanel(viewModel = viewModel, editingId = editing, onDismiss = { soundPanelFor = null })
                            }
                            PanelKind.STICKERS -> Column(modifier = Modifier.padding(bottom = AdGagSpacing.sm.dp)) {
                                val editing = stickerPanelFor?.ifEmpty { null }
                                StickerPanelHeader(viewModel = viewModel, editingId = editing, onDismiss = { stickerPanelFor = null })
                                StickerPanel(viewModel = viewModel, editingId = editing, onDismiss = { stickerPanelFor = null })
                            }
                            PanelKind.TEXT -> Column(modifier = Modifier.padding(bottom = AdGagSpacing.sm.dp)) {
                                editingTextId?.let { id ->
                                    TextEditorPanel(viewModel = viewModel, layerId = id, onDismiss = { editingTextId = null })
                                }
                            }
                            PanelKind.EDITOR -> Column(
                                modifier = Modifier.padding(
                                    start = AdGagSpacing.lg.dp,
                                    end = AdGagSpacing.lg.dp,
                                    bottom = AdGagSpacing.md.dp,
                                ),
                            ) {
                        EditorTimeline(
                            viewModel = viewModel,
                            onAddClip = {
                                viewModel.player.pause()
                                onAddClip()
                            },
                            onPickTransition = { pickingTransitionFor = it },
                            onOpenMusic = { showMusicSheet = true },
                            onAddText = addText,
                            onEditText = editOverlay,
                            onAddSpeedRange = openSpeed,
                            onEditSpeedRange = { speedSheetFor = it },
                        )
                        Spacer(modifier = Modifier.height(AdGagSpacing.md.dp))

                        ToolRow(
                            viewModel = viewModel,
                            onMusic = { if (viewModel.musicPath != null) showMusicSheet = true else pickMusic.launch("audio/*") },
                            onSpeed = openSpeed,
                            onEffects = { showEffectsSheet = true },
                            onText = addText,
                            onStickers = openStickers,
                            onSounds = openSounds,
                        )

                        viewModel.notice?.let { notice ->
                            Spacer(modifier = Modifier.height(AdGagSpacing.sm.dp))
                            Text(text = notice, color = AdGagColors.OnSurfaceMuted, style = MaterialTheme.typography.bodySmall)
                        }
                        if (viewModel.isExporting) {
                            Spacer(modifier = Modifier.height(AdGagSpacing.md.dp))
                            ExportProgress(viewModel.exportProgress)
                        }
                        if (viewModel.isAttachingMusic) {
                            Spacer(modifier = Modifier.height(AdGagSpacing.sm.dp))
                            PreparingMusicIndicator()
                        }
                        // Errors are capped at a few lines: a long codec dump used
                        // to grow the panel and squeeze the video away.
                        val previewError = viewModel.previewError
                        if (previewError != null) {
                            Spacer(modifier = Modifier.height(AdGagSpacing.sm.dp))
                            Text(
                                text = tr("Preview problem: {0}", previewError),
                                color = AdGagColors.Danger,
                                style = MaterialTheme.typography.bodySmall,
                                maxLines = 3,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                        val error = viewModel.exportError
                        if (error != null) {
                            Spacer(modifier = Modifier.height(AdGagSpacing.sm.dp))
                            Text(
                                text = tr("Export failed: {0}", error),
                                color = AdGagColors.Danger,
                                style = MaterialTheme.typography.bodySmall,
                                maxLines = 3,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }

                            }
                        }
                    }
                }
            }
        }

        if (pickingTransitionFor >= 0) {
            TransitionPickerSheet(
                viewModel = viewModel,
                boundary = pickingTransitionFor,
                onDismiss = { pickingTransitionFor = -1 },
            )
        }
        if (showMusicSheet && viewModel.musicPath != null) {
            MusicSheet(
                viewModel = viewModel,
                onReplace = {
                    showMusicSheet = false
                    pickMusic.launch("audio/*")
                },
                onDismiss = { showMusicSheet = false },
            )
        }
        speedSheetFor?.let { id ->
            SpeedRangeSheet(viewModel = viewModel, rangeId = id, onDismiss = { speedSheetFor = null })
        }
        if (showEffectsSheet) {
            EffectsSheet(viewModel = viewModel, onDismiss = { showEffectsSheet = false })
        }

    }
}

/**
 * Scale that makes the preview fit its [areaW] x [areaH] area after a 90/270°
 * rotation: ContentFrame fits the UNturned picture; turned, its bounding box
 * swaps width and height. 1 when not turned a quarter.
 */
@UnstableApi
private fun quarterTurnFit(viewModel: EditorViewModel, areaW: Float, areaH: Float): Float {
    if (viewModel.rotationDegrees % 180 != 90 || areaW <= 0f || areaH <= 0f) return 1f
    // outputAspect is AFTER the user's rotation; the picture ContentFrame fits is before it.
    val sourceAspect = 1f / viewModel.outputAspect
    val (w, h) = if (areaW / areaH > sourceAspect) areaH * sourceAspect to areaH else areaW to areaW / sourceAspect
    return minOf(areaW / h, areaH / w)
}

/**
 * The pose of whichever clip is on screen at GLOBAL time [globalMs]: its
 * entrance (from the boundary before it) and fade-out (from the boundary
 * after it), via the same TransitionMath the export uses.
 */
@UnstableApi
private fun transitionPoseAt(viewModel: EditorViewModel, globalMs: Long): TransitionMath.Pose {
    val clips = viewModel.clips
    var start = 0L
    for (i in clips.indices) {
        val end = start + clips[i].keptDurationMs
        if (globalMs < end || i == clips.lastIndex) {
            return TransitionMath.clipPose(
                entry = viewModel.transitions.getOrNull(i - 1),
                exit = viewModel.transitions.getOrNull(i),
                // Transition timing is OUTPUT time (matches the export).
                keptMs = viewModel.toOutputMs(end) - viewModel.toOutputMs(start),
                localMs = viewModel.toOutputMs(globalMs) - viewModel.toOutputMs(start),
            )
        }
        start = end
    }
    return TransitionMath.Identity
}

@Composable
private fun ToolRow(
    viewModel: EditorViewModel,
    onMusic: () -> Unit,
    onSpeed: () -> Unit,
    onEffects: () -> Unit,
    onText: () -> Unit,
    onStickers: () -> Unit,
    onSounds: () -> Unit,
) {
    Row(
        // Scrolls sideways if the tools outgrow a narrow screen.
        modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(AdGagSpacing.lg.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        EditorToolButton(
            icon = Icons.Filled.TextFields,
            label = if (viewModel.textLayers.isEmpty()) tr("Text") else tr("Text ({0})", viewModel.textLayers.size),
            active = viewModel.textLayers.isNotEmpty(),
            onClick = onText,
        )
        EditorToolButton(
            icon = Icons.Filled.EmojiEmotions,
            label = if (viewModel.stickerLayers.isEmpty()) tr("Stickers") else tr("Stickers ({0})", viewModel.stickerLayers.size),
            active = viewModel.stickerLayers.isNotEmpty(),
            onClick = onStickers,
        )
        EditorToolButton(
            icon = Icons.Filled.GraphicEq,
            label = if (viewModel.soundLayers.isEmpty()) tr("Sound FX") else tr("Sound FX ({0})", viewModel.soundLayers.size),
            active = viewModel.soundLayers.isNotEmpty(),
            onClick = onSounds,
        )
        EditorToolButton(
            icon = Icons.Filled.RotateRight,
            label = tr("Rotate"),
            onClick = { viewModel.rotateNinety() },
        )
        EditorToolButton(
            icon = if (viewModel.isMuted) Icons.Filled.VolumeOff else Icons.Filled.VolumeUp,
            label = if (viewModel.isMuted) tr("Muted") else tr("Mute"),
            active = viewModel.isMuted,
            onClick = { viewModel.toggleMute() },
        )
        EditorToolButton(
            icon = Icons.Filled.SlowMotionVideo,
            label = if (viewModel.speedRanges.isEmpty()) tr("Slow-mo") else tr("Slow-mo ({0})", viewModel.speedRanges.size),
            active = viewModel.speedRanges.isNotEmpty(),
            onClick = onSpeed,
        )
        EditorToolButton(
            icon = Icons.Filled.AutoFixHigh,
            label = if (viewModel.videoFilter == VideoFilter.NONE) tr("Effects") else viewModel.videoFilter.label,
            active = viewModel.videoFilter != VideoFilter.NONE,
            onClick = onEffects,
        )
        EditorToolButton(
            icon = if (viewModel.musicPath != null) Icons.Filled.MusicNote else Icons.Filled.MusicOff,
            label = if (viewModel.musicPath != null) tr("Music") else tr("Add music"),
            active = viewModel.musicPath != null,
            onClick = onMusic,
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
                .background(if (active) AdGagColors.Accent.copy(alpha = 0.25f) else AdGagColors.Surface),
            contentAlignment = Alignment.Center,
        ) {
            IconButton(onClick = onClick) {
                Icon(
                    imageVector = icon,
                    contentDescription = label,
                    tint = if (active) AdGagColors.Accent else AdGagColors.OnBackground,
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
                text = tr("Next"),
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
            text = tr("Exporting your Ad…"),
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

private enum class PanelKind { EDITOR, TEXT, STICKERS, SOUNDS }

/**
 * Grab bar on top of the bottom panel: drag it down to collapse the panel
 * (the video grows into the freed space), up (or tap) to bring it back.
 * While collapsed it shows which panel is hidden, plus Done for the text /
 * sticker editors so they can be closed without expanding.
 */
@Composable
private fun PanelHandle(
    collapsed: Boolean,
    label: String,
    onCollapsedChange: (Boolean) -> Unit,
    onDone: (() -> Unit)?,
) {
    val change by rememberUpdatedState(onCollapsedChange)
    val isCollapsed by rememberUpdatedState(collapsed)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .pointerInput(Unit) {
                var travelled = 0f
                detectVerticalDragGestures(
                    onDragStart = { travelled = 0f },
                    onDragEnd = {
                        val threshold = 36.dp.toPx()
                        if (travelled > threshold) change(true) else if (travelled < -threshold) change(false)
                    },
                ) { pointer, dy ->
                    pointer.consume()
                    travelled += dy
                }
            }
            .clickable { change(!isCollapsed) }
            .padding(top = AdGagSpacing.sm.dp, bottom = if (collapsed) AdGagSpacing.xs.dp else AdGagSpacing.sm.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .width(44.dp)
                .height(5.dp)
                .clip(RoundedCornerShape(AdGagRadius.pill.dp))
                .background(Color.White.copy(alpha = 0.35f)),
        )
        if (collapsed) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = AdGagSpacing.lg.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = tr("{0} · drag up to edit", label),
                    color = AdGagColors.OnSurfaceMuted,
                    style = MaterialTheme.typography.labelMedium,
                )
                if (onDone != null) {
                    TextButton(onClick = onDone) {
                        Text(text = tr("Done"), color = AdGagColors.Accent, style = MaterialTheme.typography.labelLarge)
                    }
                } else {
                    Spacer(modifier = Modifier.height(40.dp))
                }
            }
        }
    }
}
