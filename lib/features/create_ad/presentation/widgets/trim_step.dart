import "dart:async" show StreamSubscription, unawaited;
import "dart:io";
import "dart:math" show max, pi;

import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:image_picker/image_picker.dart";
import "package:uuid/uuid.dart";
import "package:video_player/video_player.dart";

import "../../../../core/media/media_providers.dart";
import "../../../../core/router/app_shell.dart";
import "../../../../core/media/video_editor_service.dart";
import "../../../../core/media/video_export_service.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../domain/local_video_draft.dart";
import "../../domain/video_constraints.dart";
import "../../domain/video_project.dart";
import "../providers/create_ad_flow_controller.dart";
import "../providers/editor_controller.dart";

/// The creation flow's one editing step (CLAUDE.md section 4/38): trim,
/// rotate, flip, mute, a color filter, background music, slow-motion
/// zones, and timed text/sticker overlays, all on a single screen with a
/// timeline. Not split into a separate "basic" vs. "advanced" screen — a
/// slow-motion zone is just another tool next to rotate, not a different
/// product.
///
/// Two render paths, picked automatically at "Continue", not exposed to
/// the user as a choice: a plain trim/rotate/flip/mute edit (no zones, no
/// overlays) goes through the fast `easy_video_editor` pipeline
/// ([VideoEditorService]); the moment a speed zone or overlay is added,
/// everything (including trim/rotate/flip/mute) renders in one pass
/// through the FFmpeg pipeline ([VideoExportService]) instead, so the
/// user never sees "export" as a separate concept from "continue" — it's
/// just what continuing costs when the edit needs it.
class TrimStep extends ConsumerStatefulWidget {
  const TrimStep({super.key});

  @override
  ConsumerState<TrimStep> createState() => _TrimStepState();
}

class _TrimStepState extends ConsumerState<TrimStep> {
  static const Uuid _uuid = Uuid();

  VideoPlayerController? _controller;

  // The trim window's *end* the first time this screen loads a clip —
  // needed by both EditorController.init() and Reset (which restores
  // this exact untouched window, not an empty/zero one).
  Duration _initialTrimEnd = Duration.zero;

  bool _processing = false;
  double _progress = 0;
  StreamSubscription<double>? _progressSub;
  String? _error;

  // Live-preview-only state (never exported — the real render always goes
  // through VideoFilterGraphBuilder/FfmpegVideoExportService). A second
  // VideoPlayerController plays the picked music file in sync with the
  // main preview rather than adding a dedicated audio-player dependency —
  // video_player's native ExoPlayer/AVPlayer backing plays audio-only
  // files fine, and this project's history this session (file_picker,
  // share_plus, ffmpeg_kit) is full of new-native-dependency Kotlin/AGP
  // conflicts worth avoiding when an already-vetted package can do it.
  VideoPlayerController? _musicController;
  double? _lastAppliedPreviewSpeed;

  // Real decoded frames for the timeline's Clip lane (not a placeholder
  // bar — see the video-editor spec this round implements). Generated
  // once against the *original* captured file, independent of trim/edits,
  // since the filmstrip represents the whole source clip the same way
  // the base track already does. Empty until generation finishes, and
  // stays empty (falling back to the plain lane background) if it fails
  // — a missing filmstrip should never block editing.
  List<String> _thumbnailPaths = <String>[];

  bool _showFilterStrip = false;

  @override
  void initState() {
    super.initState();
    final LocalVideoDraft? draft = ref.read(createAdFlowControllerProvider).capturedDraft;
    if (draft != null) {
      final VideoPlayerController controller = VideoPlayerController.file(File(draft.filePath));
      _controller = controller;
      unawaited(
        controller.initialize().then((_) {
          if (mounted) {
            final Duration total = controller.value.duration;
            _initialTrimEnd = total > VideoConstraints.max ? VideoConstraints.max : total;
            // VideoProject becomes the single source of truth from this
            // point on — the preview below reads it directly, not a
            // parallel copy of these fields kept in widget state.
            ref.read(editorControllerProvider.notifier).init(
                  VideoProject(videoPath: draft.filePath, trimStart: Duration.zero, trimEnd: _initialTrimEnd),
                );
            setState(() {});
            unawaited(controller.setLooping(true));
            unawaited(controller.play());
            controller.addListener(_syncLivePreview);
            unawaited(_generateThumbnails(draft));
          }
        }),
      );
    }
  }

  Future<void> _generateThumbnails(LocalVideoDraft draft) async {
    final List<String> paths = await ref.read(videoThumbnailServiceProvider).generateThumbnails(
          videoPath: draft.filePath,
          duration: draft.duration,
          count: 10,
        );
    if (mounted && paths.isNotEmpty) {
      setState(() => _thumbnailPaths = paths);
    }
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _controller?.dispose().ignore();
    _musicController?.dispose().ignore();
    // Stops an in-flight thumbnail generation and deletes whatever it
    // had already written — leaving the editor before generation
    // finishes shouldn't leak temp JPEGs for the rest of the session.
    unawaited(ref.read(videoThumbnailServiceProvider).cancel());
    // Whatever happens next (successful Continue, Retake, or the shell
    // itself navigating away after confirmation) means there's nothing
    // left on *this* screen to warn about losing.
    ref.read(hasUnsavedCreateEditsProvider.notifier).state = false;
    super.dispose();
  }

  /// Drives both live-preview approximations that don't otherwise show up
  /// until export: a speed zone's slow/fast motion (via the *same*
  /// controller's own `setPlaybackSpeed`, only changed when the active
  /// zone actually changes — not every tick, since it's a platform call)
  /// and background music (played/paused/seeked on `_musicController` to
  /// track whichever window of the main clip is currently showing).
  /// Approximation, not a promise of an exact match: `setPlaybackSpeed`
  /// pitch-shifts the *preview's* audio the way most players do, where
  /// the real export uses FFmpeg's `atempo` to keep pitch correct — only
  /// the preview has this limitation, matching the same
  /// preview-vs-render approximation this screen already makes for color
  /// filters (`ColorFilter.matrix` vs. FFmpeg's `eq`/`hue`).
  void _syncLivePreview() {
    final VideoPlayerController? controller = _controller;
    final VideoProject? project = ref.read(editorControllerProvider);
    if (controller == null || !controller.value.isInitialized || project == null) {
      return;
    }
    final double startSeconds = project.trimStart.inMilliseconds / 1000.0;
    final double elapsedInTrim = controller.value.position.inMilliseconds / 1000.0 - startSeconds;

    double desiredSpeed = 1.0;
    for (final SpeedZone zone in project.speedZones) {
      final double zoneStart = zone.start.inMilliseconds / 1000.0;
      final double zoneEnd = zone.end.inMilliseconds / 1000.0;
      if (elapsedInTrim >= zoneStart && elapsedInTrim < zoneEnd) {
        desiredSpeed = zone.factor;
        break;
      }
    }
    if (_lastAppliedPreviewSpeed != desiredSpeed) {
      _lastAppliedPreviewSpeed = desiredSpeed;
      unawaited(controller.setPlaybackSpeed(desiredSpeed));
    }

    final VideoPlayerController? music = _musicController;
    final BackgroundAudio? bg = project.bgAudio;
    if (music == null || bg == null || !music.value.isInitialized) {
      return;
    }
    final double musicStart = bg.startSec.inMilliseconds / 1000.0;
    final double musicDuration =
        (bg.duration ?? (project.trimmedDuration - bg.startSec)).inMilliseconds / 1000.0;
    final bool inMusicWindow = elapsedInTrim >= musicStart && elapsedInTrim < musicStart + musicDuration;
    if (inMusicWindow) {
      if (!music.value.isPlaying) {
        final Duration seekTo = Duration(milliseconds: ((elapsedInTrim - musicStart) * 1000).round());
        unawaited(music.seekTo(seekTo.isNegative ? Duration.zero : seekTo));
        unawaited(music.play());
      }
    } else if (music.value.isPlaying) {
      unawaited(music.pause());
    }
  }

  /// Creates/replaces/tears down `_musicController` to match [audio], and
  /// writes [audio] into [VideoProject] via [EditorController] — the
  /// single place background music should be written from, so the
  /// preview player never drifts out of sync with the composition (the
  /// timeline's resize/remove callbacks and the music-picker dialog both
  /// go through this instead of writing the composition directly).
  Future<void> _setBgAudio(BackgroundAudio? audio) async {
    final EditorController notifier = ref.read(editorControllerProvider.notifier);
    final bool sourceChanged = ref.read(editorControllerProvider)?.bgAudio?.filePath != audio?.filePath;
    notifier.setBgAudio(audio);
    if (!sourceChanged) {
      if (audio != null) {
        unawaited(_musicController?.setVolume(audio.volume));
      }
      return;
    }
    final VideoPlayerController? old = _musicController;
    _musicController = null;
    await old?.pause();
    await old?.dispose();
    if (audio == null) {
      return;
    }
    final VideoPlayerController controller = VideoPlayerController.file(File(audio.filePath));
    try {
      await controller.initialize();
      await controller.setVolume(audio.volume);
      if (mounted) {
        setState(() => _musicController = controller);
      }
    } catch (_) {
      // The picked file's format isn't one the platform player can open
      // for live preview — FFmpeg's format support at export time is far
      // broader than video_player's, so this only affects the in-editor
      // preview, not whether the music actually ends up in the published
      // Ad. Surface it rather than silently doing nothing, but don't
      // block anything.
      await controller.dispose();
      if (mounted) {
        _showSnack("Couldn't preview this audio here — it'll still be used when you publish.");
      }
    }
  }

  /// trimStart/trimEnd are independently stored on [VideoProject] now
  /// (each edge is its own draggable handle — see [_Timeline]), not
  /// "start plus an auto-derived up-to-10s end" the way the single
  /// drag-to-move trim window used to work, so this is just the
  /// composition's own duration, not a recomputation.
  Duration get _trimmedDuration => ref.read(editorControllerProvider)?.trimmedDuration ?? Duration.zero;

  /// Drags the LEFT edge of the trim selection — the RIGHT edge
  /// (trimEnd) stays fixed, duration is clamped to
  /// [VideoConstraints.min, VideoConstraints.max], matching how a
  /// phone's native gallery/video editor trims (independent edges, not
  /// "move a fixed-length window").
  void _applyTrimStartEdge(double startSeconds) {
    final VideoProject? project = ref.read(editorControllerProvider);
    if (project == null) {
      return;
    }
    final Duration end = project.trimEnd;
    Duration start = Duration(milliseconds: (startSeconds * 1000).round());
    if (start < Duration.zero) {
      start = Duration.zero;
    }
    final Duration minStart = end - VideoConstraints.max;
    final Duration maxStart = end - VideoConstraints.min;
    if (start < minStart && minStart > Duration.zero) {
      start = minStart;
    }
    if (start > maxStart) {
      start = maxStart;
    }
    ref.read(editorControllerProvider.notifier).setTrim(start: start, end: end);
    unawaited(_controller?.seekTo(start));
  }

  /// Drags the RIGHT edge — the LEFT edge (trimStart) stays fixed, same
  /// duration clamp as the left handle.
  void _applyTrimEndEdge(double endSeconds) {
    final VideoProject? project = ref.read(editorControllerProvider);
    final Duration? total = _controller?.value.duration;
    if (project == null || total == null) {
      return;
    }
    final Duration start = project.trimStart;
    Duration end = Duration(milliseconds: (endSeconds * 1000).round());
    if (end > total) {
      end = total;
    }
    final Duration minEnd = start + VideoConstraints.min;
    final Duration maxEnd = start + VideoConstraints.max;
    if (end < minEnd) {
      end = minEnd;
    }
    if (end > maxEnd) {
      end = maxEnd > total ? total : maxEnd;
    }
    ref.read(editorControllerProvider.notifier).setTrim(start: start, end: end);
  }

  void _cycleRotation() {
    final AppVideoRotation current = ref.read(editorControllerProvider)?.rotation ?? AppVideoRotation.none;
    final AppVideoRotation next = switch (current) {
      AppVideoRotation.none => AppVideoRotation.degrees90,
      AppVideoRotation.degrees90 => AppVideoRotation.degrees180,
      AppVideoRotation.degrees180 => AppVideoRotation.degrees270,
      AppVideoRotation.degrees270 => AppVideoRotation.none,
    };
    ref.read(editorControllerProvider.notifier).setRotation(next);
  }

  void _toggleFlip(AppFlipDirection direction) {
    final AppFlipDirection current = ref.read(editorControllerProvider)?.flip ?? AppFlipDirection.none;
    ref.read(editorControllerProvider.notifier).setFlip(current == direction ? AppFlipDirection.none : direction);
  }

  void _toggleRemoveAudio() {
    final bool current = ref.read(editorControllerProvider)?.removeAudio ?? false;
    ref.read(editorControllerProvider.notifier).setRemoveAudio(!current);
    unawaited(_controller?.setVolume(!current ? 0 : 1));
  }

  void _toggleFilterStrip() {
    setState(() => _showFilterStrip = !_showFilterStrip);
  }

  Future<void> _addSpeedZone() async {
    final SpeedZone? zone = await showDialog<SpeedZone>(
      context: context,
      builder: (BuildContext context) => _SpeedZoneDialog(maxDuration: _trimmedDuration),
    );
    if (zone == null) {
      return;
    }
    final List<SpeedZone> existing = ref.read(editorControllerProvider)?.speedZones ?? const <SpeedZone>[];
    if (existing.any((SpeedZone z) => z.overlaps(zone))) {
      _showSnack("That overlaps an existing speed zone.");
      return;
    }
    ref.read(editorControllerProvider.notifier).addSpeedZone(zone);
  }

  /// Drag-resize from the timeline's own edge handles (see [_Timeline]) —
  /// distinct from `_addSpeedZone`'s overlap check, since a zone shrinking
  /// or growing against its own previous bounds isn't "overlapping
  /// itself"; a stray drag past a neighboring zone is left uncorrected on
  /// purpose (rare with the zone counts this editor sees, and clamping
  /// against every sibling on every drag frame isn't worth the
  /// complexity yet).
  void _onResizeZone(SpeedZone oldZone, SpeedZone updated) {
    ref.read(editorControllerProvider.notifier).resizeSpeedZone(oldZone, updated);
  }

  void _onResizeOverlay(VideoOverlay oldOverlay, VideoOverlay updated) {
    ref.read(editorControllerProvider.notifier).updateOverlay(updated);
  }

  Future<void> _addTextOverlay() async {
    final TextOverlay? overlay = await showDialog<TextOverlay>(
      context: context,
      builder: (BuildContext context) => _TextOverlayDialog(id: _uuid.v4(), maxDuration: _trimmedDuration),
    );
    if (overlay != null) {
      ref.read(editorControllerProvider.notifier).addOverlay(overlay);
    }
  }

  /// "Sticker" used to just open the device gallery directly, with no
  /// actual sticker library — this offers a curated preset set first
  /// (rendered as [TextOverlay]s, reusing the exact font/drawtext path
  /// already verified working, rather than a new image-compositing
  /// route that would need its own verification) with "choose from
  /// gallery" as an explicit secondary option, not the only one.
  Future<void> _addSticker() async {
    final _StickerChoice? choice = await showDialog<_StickerChoice>(
      context: context,
      builder: (BuildContext context) => const _StickerPickerDialog(),
    );
    if (choice == null || !mounted) {
      return;
    }
    switch (choice) {
      case _StickerSymbolChoice(:final String symbol):
        final _TimeRange? range = await showDialog<_TimeRange>(
          context: context,
          builder: (BuildContext context) => _TimeRangeDialog(maxDuration: _trimmedDuration),
        );
        if (range == null || !mounted) {
          return;
        }
        ref.read(editorControllerProvider.notifier).addOverlay(
              TextOverlay(
                id: _uuid.v4(),
                xPercent: 0.4,
                yPercent: 0.3,
                startSec: range.start,
                duration: range.end - range.start,
                text: symbol,
                fontSize: 64,
              ),
            );
      case _StickerGalleryChoice():
        await _addImageOverlayFromGallery();
    }
  }

  Future<void> _addImageOverlayFromGallery() async {
    final XFile? file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (file == null || !mounted) {
      return;
    }
    final _TimeRange? range = await showDialog<_TimeRange>(
      context: context,
      builder: (BuildContext context) => _TimeRangeDialog(maxDuration: _trimmedDuration),
    );
    if (range == null) {
      return;
    }
    ref.read(editorControllerProvider.notifier).addOverlay(
          ImageOverlay(
            id: _uuid.v4(),
            xPercent: 0.35,
            yPercent: 0.35,
            startSec: range.start,
            duration: range.end - range.start,
            assetPath: file.path,
          ),
        );
  }

  Future<void> _pickMusic() async {
    final PlatformFile? picked = await FilePicker.pickFile(type: FileType.audio);
    final String? path = picked?.path;
    if (path == null || !mounted) {
      return;
    }
    final BackgroundAudio? audio = await showDialog<BackgroundAudio>(
      context: context,
      builder: (BuildContext context) => _BackgroundAudioDialog(filePath: path, maxDuration: _trimmedDuration),
    );
    if (audio != null) {
      unawaited(_setBgAudio(audio));
    }
  }

  // Baseline values captured at the start of a drag/pinch/rotate gesture
  // on an overlay — details.scale/details.rotation are cumulative from
  // gesture start, not incremental, so the "before" state has to be
  // remembered once rather than applied delta-by-delta.
  String? _gestureOverlayId;
  double _gestureBaseX = 0;
  double _gestureBaseY = 0;
  double _gestureBaseSize = 0;
  double _gestureBaseRotationDegrees = 0;
  Offset _gestureStartFocalPoint = Offset.zero;

  void _onOverlayScaleStart(VideoOverlay overlay, ScaleStartDetails details) {
    _gestureOverlayId = overlay.id;
    _gestureBaseX = overlay.xPercent;
    _gestureBaseY = overlay.yPercent;
    _gestureBaseSize = switch (overlay) {
      TextOverlay(:final double fontSize) => fontSize,
      ImageOverlay(:final double widthPercent) => widthPercent,
    };
    _gestureBaseRotationDegrees = overlay is ImageOverlay ? overlay.rotationDegrees : 0;
    _gestureStartFocalPoint = details.focalPoint;
  }

  void _onOverlayScaleUpdate(VideoOverlay overlay, ScaleUpdateDetails details, Size previewSize) {
    if (_gestureOverlayId != overlay.id) {
      return;
    }
    final double dx = (details.focalPoint.dx - _gestureStartFocalPoint.dx) / previewSize.width;
    final double dy = (details.focalPoint.dy - _gestureStartFocalPoint.dy) / previewSize.height;
    final double nextX = (_gestureBaseX + dx).clamp(0.0, 1.0);
    final double nextY = (_gestureBaseY + dy).clamp(0.0, 1.0);

    final VideoOverlay updated = switch (overlay) {
      TextOverlay() => TextOverlay(
          id: overlay.id,
          xPercent: nextX,
          yPercent: nextY,
          startSec: overlay.startSec,
          duration: overlay.duration,
          text: overlay.text,
          argbColor: overlay.argbColor,
          fontSize: (_gestureBaseSize * details.scale).clamp(12.0, 96.0),
          animation: overlay.animation,
          opacity: overlay.opacity,
          hasOutline: overlay.hasOutline,
          hasShadow: overlay.hasShadow,
          hasBackground: overlay.hasBackground,
        ),
      ImageOverlay() => ImageOverlay(
          id: overlay.id,
          xPercent: nextX,
          yPercent: nextY,
          startSec: overlay.startSec,
          duration: overlay.duration,
          assetPath: overlay.assetPath,
          widthPercent: (_gestureBaseSize * details.scale).clamp(0.08, 0.9),
          rotationDegrees: _gestureBaseRotationDegrees + details.rotation * 180 / pi,
        ),
    };
    ref.read(editorControllerProvider.notifier).updateOverlay(updated);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _retake() {
    // Explicit, not just left to dispose() — dispose() only fires once
    // this widget is actually torn down, and a rebuild racing the retake
    // (e.g. the flow controller's state changing step before this
    // screen unmounts) could otherwise leave the flag stuck true, making
    // the leave-confirmation dialog fire on a screen with nothing to lose.
    ref.read(hasUnsavedCreateEditsProvider.notifier).state = false;
    ref.read(createAdFlowControllerProvider.notifier).retake();
  }

  /// Undoes every edit made on this screen — back to the untouched
  /// capture, still on this screen (unlike Retake, which discards the
  /// capture itself and goes back to record/import). Itself one more
  /// undo-able step (routed through EditorController, not a bypass of
  /// it), so hitting Reset by mistake can still be undone.
  void _reset() {
    ref.read(editorControllerProvider.notifier).resetToDefaults(_initialTrimEnd);
    unawaited(_controller?.setVolume(1));
    unawaited(_controller?.seekTo(Duration.zero));
    unawaited(_setBgAudio(null));
  }

  Future<void> _confirm() async {
    final LocalVideoDraft? draft = ref.read(createAdFlowControllerProvider).capturedDraft;
    final VideoProject? project = ref.read(editorControllerProvider);
    if (draft == null || project == null) {
      return;
    }
    setState(() {
      _processing = true;
      _progress = 0;
      _error = null;
    });

    try {
      final bool needsTrim = project.trimStart > Duration.zero || project.trimEnd < draft.duration;
      final bool hasSimpleEdit = project.rotation != AppVideoRotation.none ||
          project.flip != AppFlipDirection.none ||
          project.removeAudio;
      // Color grading has no equivalent in the fast easy_video_editor
      // pipeline (no color-filter support there), so it forces the FFmpeg
      // path the same way a speed zone or overlay does.
      final bool hasAdvancedEdit = project.speedZones.isNotEmpty ||
          project.overlays.isNotEmpty ||
          project.colorFilter != AppColorFilter.none ||
          project.bgAudio != null;

      final LocalVideoDraft finalDraft;
      if (!needsTrim && !hasSimpleEdit && !hasAdvancedEdit) {
        // Nothing was actually changed — publish the capture as-is rather
        // than paying for a no-op re-encode.
        finalDraft = draft;
      } else if (hasAdvancedEdit) {
        // project IS the composition being exported — no separate
        // reconstruction from scattered fields; preview and export read
        // the exact same object.
        final VideoExportService service = ref.read(videoExportServiceProvider);
        _progressSub = service.progress.listen((double p) {
          if (mounted) {
            setState(() => _progress = p);
          }
        });
        final String outputPath = await service.export(project);
        final Duration outputDuration = await ref.read(localVideoProberProvider).probeDuration(outputPath);
        finalDraft = LocalVideoDraft(filePath: outputPath, duration: outputDuration);
      } else {
        final VideoEditRequest request = VideoEditRequest(
          sourcePath: draft.filePath,
          trimStart: project.trimStart,
          trimEnd: project.trimEnd,
          rotation: project.rotation,
          flip: project.flip,
          removeAudio: project.removeAudio,
        );
        final String outputPath = await ref.read(videoEditorServiceProvider).apply(
              request,
              onProgress: (double p) {
                if (mounted) {
                  setState(() => _progress = p);
                }
              },
            );
        final Duration outputDuration = await ref.read(localVideoProberProvider).probeDuration(outputPath);
        finalDraft = LocalVideoDraft(filePath: outputPath, duration: outputDuration);
      }

      ref.read(createAdFlowControllerProvider.notifier).onVideoTrimmed(finalDraft);
    } catch (e) {
      setState(() => _error = "Couldn't process this clip: $e");
    } finally {
      await _progressSub?.cancel();
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? controller = _controller;
    final VideoProject? project = ref.watch(editorControllerProvider);
    final bool ready = controller != null && controller.value.isInitialized && project != null;

    final bool hasEdits = project?.hasAnyEdit ?? false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final StateController<bool> flag = ref.read(hasUnsavedCreateEditsProvider.notifier);
      if (flag.state != hasEdits) {
        flag.state = hasEdits;
      }
    });

    // Same IndexedStack problem as the feed (see app_shell.dart's doc
    // comment on activeShellBranchIndexProvider): switching to a
    // different bottom-nav tab while on this screen doesn't pause this
    // preview on its own — without this listener the clip (with audio)
    // kept playing behind whichever tab the user switched to.
    ref.listen(activeShellBranchIndexProvider, (int? previous, int next) {
      final VideoPlayerController? c = _controller;
      if (c == null || !c.value.isInitialized) {
        return;
      }
      if (next == 2) {
        unawaited(c.play());
      } else {
        unawaited(c.pause());
      }
    });

    final EditorController editorNotifier = ref.read(editorControllerProvider.notifier);

    return Scaffold(
      // Immersive per the editor spec's section 12: no title clutter, no
      // giant bottom Continue button (removed below) — "Next" is the one
      // primary action, top-right, and video stays the visual focus.
      // Undo/redo stay directly visible (used often enough that burying
      // them in a menu would cost more than the AppBar space they take);
      // Reset/Retake — rarer, more consequential actions — are grouped
      // into one overflow menu instead of their own permanent buttons.
      appBar: AppBar(
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: "Undo",
            onPressed: (_processing || !editorNotifier.canUndo) ? null : editorNotifier.undo,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: "Redo",
            onPressed: (_processing || !editorNotifier.canRedo) ? null : editorNotifier.redo,
          ),
          PopupMenuButton<VoidCallback>(
            enabled: !_processing,
            onSelected: (VoidCallback action) => action(),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<VoidCallback>>[
              PopupMenuItem<VoidCallback>(value: _reset, child: const Text("Reset edits")),
              PopupMenuItem<VoidCallback>(value: _retake, child: const Text("Retake")),
            ],
          ),
          TextButton(
            onPressed: (!ready || _processing) ? null : () => unawaited(_confirm()),
            child: Text(_processing ? "${(_progress * 100).round()}%" : "Next"),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: <Widget>[
              AspectRatio(
                aspectRatio: 9 / 16,
                child: ready
                    ? LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints constraints) {
                          final Size previewSize = Size(constraints.maxWidth, constraints.maxHeight);
                          return ColoredBox(
                            color: Colors.black,
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                Center(
                                  child: ColorFiltered(
                                    colorFilter: project.colorFilter.previewFilter,
                                    child: RotatedBox(
                                      quarterTurns: project.rotation.quarterTurns,
                                      child: Transform(
                                        alignment: Alignment.center,
                                        transform: Matrix4.diagonal3Values(
                                          project.flip == AppFlipDirection.horizontal ? -1 : 1,
                                          project.flip == AppFlipDirection.vertical ? -1 : 1,
                                          1,
                                        ),
                                        child: AspectRatio(
                                          aspectRatio: controller.value.aspectRatio,
                                          child: VideoPlayer(controller),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                for (final VideoOverlay overlay in project.overlays)
                                  Positioned(
                                    left: overlay.xPercent * previewSize.width,
                                    top: overlay.yPercent * previewSize.height,
                                    child: GestureDetector(
                                      // onScale (not onPan) so one finger
                                      // moves it, two fingers pinch to
                                      // resize and rotate (images) — all
                                      // through the same callback pair,
                                      // since a GestureDetector can't mix
                                      // onPanUpdate and onScaleUpdate
                                      // without them fighting over the
                                      // gesture arena.
                                      onScaleStart: (ScaleStartDetails d) => _onOverlayScaleStart(overlay, d),
                                      onScaleUpdate: (ScaleUpdateDetails d) =>
                                          _onOverlayScaleUpdate(overlay, d, previewSize),
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: <Widget>[
                                          _OverlayPreview(overlay: overlay, previewWidth: previewSize.width),
                                          Positioned(
                                            right: -10,
                                            top: -10,
                                            child: GestureDetector(
                                              onTap: () => ref
                                                  .read(editorControllerProvider.notifier)
                                                  .removeOverlay(overlay.id),
                                              child: Container(
                                                width: 22,
                                                height: 22,
                                                decoration: const BoxDecoration(
                                                  color: Colors.black87,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.close, size: 14, color: Colors.white),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      )
                    : const ColoredBox(
                        color: Colors.black12,
                        child: Center(child: CircularProgressIndicator()),
                      ),
              ),
              const SizedBox(height: AppSpacing.lg),

              if (ready) ...<Widget>[
                SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: <Widget>[
                      _ToolButton(
                        icon: Icons.rotate_90_degrees_cw_outlined,
                        label: project.rotation == AppVideoRotation.none ? "Rotate" : "${project.rotation.value}°",
                        selected: project.rotation != AppVideoRotation.none,
                        onTap: _cycleRotation,
                      ),
                      _ToolButton(
                        icon: Icons.flip,
                        label: "Flip H",
                        selected: project.flip == AppFlipDirection.horizontal,
                        onTap: () => _toggleFlip(AppFlipDirection.horizontal),
                      ),
                      _ToolButton(
                        icon: Icons.flip,
                        label: "Flip V",
                        selected: project.flip == AppFlipDirection.vertical,
                        onTap: () => _toggleFlip(AppFlipDirection.vertical),
                        iconTurns: 1,
                      ),
                      _ToolButton(
                        icon: project.removeAudio ? Icons.volume_off : Icons.volume_up,
                        label: "Mute",
                        selected: project.removeAudio,
                        onTap: _toggleRemoveAudio,
                      ),
                      _ToolButton(
                        icon: Icons.palette_outlined,
                        label: project.colorFilter.label,
                        selected: project.colorFilter != AppColorFilter.none || _showFilterStrip,
                        onTap: _toggleFilterStrip,
                      ),
                      _ToolButton(
                        icon: Icons.music_note_outlined,
                        label: "Music",
                        selected: project.bgAudio != null,
                        onTap: () => unawaited(_pickMusic()),
                      ),
                      _ToolButton(
                        icon: Icons.slow_motion_video_outlined,
                        label: "Slow-mo",
                        onTap: () => unawaited(_addSpeedZone()),
                      ),
                      _ToolButton(
                        icon: Icons.text_fields,
                        label: "Text",
                        onTap: () => unawaited(_addTextOverlay()),
                      ),
                      _ToolButton(
                        icon: Icons.emoji_emotions_outlined,
                        label: "Sticker",
                        onTap: () => unawaited(_addSticker()),
                      ),
                    ],
                  ),
                ),

                if (_showFilterStrip) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 76,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: <Widget>[
                        for (final AppColorFilter filter in AppColorFilter.values)
                          _FilterPreviewChip(
                            filter: filter,
                            thumbnailPath: _thumbnailPaths.isNotEmpty ? _thumbnailPaths.first : null,
                            selected: project.colorFilter == filter,
                            onTap: () => ref.read(editorControllerProvider.notifier).setColorFilter(filter),
                          ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: AppSpacing.md),
                _Timeline(
                  controller: controller,
                  thumbnailPaths: _thumbnailPaths,
                  originalDuration: controller.value.duration,
                  trimStartSeconds: project.trimStart.inMilliseconds / 1000.0,
                  trimmedDuration: _trimmedDuration,
                  onTrimStartChanged: _applyTrimStartEdge,
                  onTrimEndChanged: _applyTrimEndEdge,
                  speedZones: project.speedZones,
                  overlays: project.overlays,
                  bgAudio: project.bgAudio,
                  onRemoveZone: (SpeedZone z) => ref.read(editorControllerProvider.notifier).removeSpeedZone(z),
                  onResizeZone: _onResizeZone,
                  onRemoveOverlay: (String id) => ref.read(editorControllerProvider.notifier).removeOverlay(id),
                  onResizeOverlay: _onResizeOverlay,
                  onResizeMusic: (BackgroundAudio updated) => unawaited(_setBgAudio(updated)),
                  onRemoveMusic: () => unawaited(_setBgAudio(null)),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),

              if (_processing)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: LinearProgressIndicator(value: _progress > 0 ? _progress : null),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.iconTurns = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final int iconTurns;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          width: 68,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withValues(alpha: 0.15) : null,
            border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              RotatedBox(quarterTurns: iconTurns, child: Icon(icon, size: 20)),
              const SizedBox(height: 2),
              Text(label, style: Theme.of(context).textTheme.labelSmall, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

/// One entry in the horizontal filter picker (CLAUDE.md-adjacent spec
/// section 10: "horizontally scrollable filter selector with visual
/// previews," not a bare label). Uses a real frame from the clip's own
/// filmstrip when one's available (same thumbnails the timeline shows)
/// so the preview is the actual footage, not a generic swatch; falls
/// back to a plain tinted square before thumbnails finish generating.
class _FilterPreviewChip extends StatelessWidget {
  const _FilterPreviewChip({
    required this.filter,
    required this.thumbnailPath,
    required this.selected,
    required this.onTap,
  });

  final AppColorFilter filter;
  final String? thumbnailPath;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? path = thumbnailPath;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm - 2),
                child: ColorFiltered(
                  colorFilter: filter.previewFilter,
                  child: path != null
                      ? Image.file(File(path), fit: BoxFit.cover, width: 52, height: 52)
                      : ColoredBox(color: scheme.surfaceContainerHighest),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(filter.label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

/// The timeline: a visibly bounded panel (a bordered/tinted [Container],
/// not empty space) with a fixed-width label column on the left naming
/// each lane ("Clip", "Speed", "Music", "Text") and, to the right, a
/// time-mapped track area per lane — a lane's background is drawn even
/// when it's empty, so it's clear that's the region a slow-mo zone or
/// music clip would occupy, not an arbitrary gap.
///
/// Centered-playhead, horizontally-scrolling (spec section 3: "the
/// playhead should preferably remain centered while the timeline moves
/// underneath it" — the standard mobile pattern, not desktop's
/// drag-a-marker-across-a-fixed-ruler). Content lays out at a fixed
/// [_TimelineState._pixelsPerSecond] scale, not stretched to the
/// viewport, so there's always real horizontal scroll even for this
/// format's short (<=10s) clips — scale is what makes the ruler/chips
/// legible, not how much content there is. The ruler shows a tick +
/// number per second; the whole scrollable area is the scrub surface
/// (drag anywhere to seek); a static playhead line (outside the scroll
/// view, `IgnorePointer`) marks "now."
///
/// The Clip lane's trim selection is two independent edge handles (drag
/// left to change where the clip starts, drag right to change where it
/// ends — a phone gallery editor's model, not one draggable window of a
/// fixed length) over a clean filmstrip, with the excluded portions
/// dimmed rather than the selected portion filled — no permanent colored
/// block sits over the thumbnails.
///
/// Speed-zone, music, and overlay items are all directly drag-resizable
/// from their own left/right edge handles (a visibly larger grip than a
/// plain body tap, hit area roughly twice the visual size), in addition
/// to tap-to-remove on the body of the chip/bar. Every chip also prints
/// its own start–end time under its label.
class _Timeline extends StatefulWidget {
  const _Timeline({
    required this.controller,
    required this.thumbnailPaths,
    required this.originalDuration,
    required this.trimStartSeconds,
    required this.trimmedDuration,
    required this.onTrimStartChanged,
    required this.onTrimEndChanged,
    required this.speedZones,
    required this.overlays,
    required this.bgAudio,
    required this.onRemoveZone,
    required this.onResizeZone,
    required this.onRemoveOverlay,
    required this.onResizeOverlay,
    required this.onResizeMusic,
    required this.onRemoveMusic,
  });

  final VideoPlayerController controller;
  final List<String> thumbnailPaths;
  final Duration originalDuration;
  final double trimStartSeconds;
  final Duration trimmedDuration;
  final ValueChanged<double> onTrimStartChanged;
  final ValueChanged<double> onTrimEndChanged;
  final List<SpeedZone> speedZones;
  final List<VideoOverlay> overlays;
  final BackgroundAudio? bgAudio;
  final void Function(SpeedZone) onRemoveZone;
  final void Function(SpeedZone oldZone, SpeedZone updated) onResizeZone;
  final void Function(String) onRemoveOverlay;
  final void Function(VideoOverlay oldOverlay, VideoOverlay updated) onResizeOverlay;
  final void Function(BackgroundAudio updated) onResizeMusic;
  final VoidCallback onRemoveMusic;

  static const double _labelWidth = 52;
  static const double _rulerHeight = 22;
  static const double _trimLaneHeight = 44;
  static const double _laneHeight = 40;
  static const double _laneGap = 6;
  static const Duration _minZoneDuration = Duration(milliseconds: 300);

  static String _fmt(Duration d) => "${(d.inMilliseconds / 1000.0).toStringAsFixed(1)}s";

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  /// Fixed regardless of clip length or viewport width — legibility
  /// (ruler ticks, chip labels) is what sets this, not "does the content
  /// fit the screen." At 70px/s a 10s clip is 700px wide, comfortably
  /// scrollable on any phone.
  static const double _pixelsPerSecond = 70;
  static const double _textRowGap = 4;

  late final ScrollController _scrollController;

  /// True only while an actual user drag is moving the scroll view —
  /// distinguishes a user scrubbing (which should drive `seekTo`) from
  /// this widget's own `jumpTo` calls following normal playback (which
  /// must NOT feed back into another seek, or forward playback and
  /// auto-scroll would fight each other every frame).
  bool _isUserScrubbing = false;

  /// True while a trim-handle or edge-resize drag is in progress, so the
  /// ScrollView's own physics can be disabled for that gesture — without
  /// this, a drag that starts on a resize handle is ambiguous with "drag
  /// to scroll the timeline" and the outer ScrollView tends to win,
  /// since both are the same axis. Genuinely the single highest-risk
  /// piece of this widget to get right without a physical device — see
  /// this round's CLAUDE.md entry.
  bool _gestureLockScroll = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    widget.controller.addListener(_onPlaybackPositionChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onPlaybackPositionChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onPlaybackPositionChanged() {
    if (_isUserScrubbing || !mounted || !_scrollController.hasClients) {
      return;
    }
    final double sec = widget.controller.value.position.inMilliseconds / 1000.0;
    final double target = sec * _pixelsPerSecond;
    final ScrollPosition position = _scrollController.position;
    _scrollController.jumpTo(target.clamp(position.minScrollExtent, position.maxScrollExtent));
  }

  void _setGestureLock(bool locked) {
    if (_gestureLockScroll != locked) {
      setState(() => _gestureLockScroll = locked);
    }
  }

  Future<void> _confirmRemoveZone(BuildContext context, SpeedZone zone) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text("Remove this speed zone?"),
        content: Text("${zone.factor}x from ${zone.start.inSeconds}s to ${zone.end.inSeconds}s."),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text("Remove")),
        ],
      ),
    );
    if (confirmed == true) {
      widget.onRemoveZone(zone);
    }
  }

  Future<void> _confirmRemoveOverlay(BuildContext context, VideoOverlay overlay) async {
    final String label = overlay is TextOverlay ? '"${overlay.text}"' : "this sticker";
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text("Remove this?"),
        content: Text("Removes $label from the video."),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text("Remove")),
        ],
      ),
    );
    if (confirmed == true) {
      widget.onRemoveOverlay(overlay.id);
    }
  }

  Future<void> _confirmRemoveMusic(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text("Remove this music?"),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text("Remove")),
        ],
      ),
    );
    if (confirmed == true) {
      widget.onRemoveMusic();
    }
  }

  Widget _lane(ColorScheme scheme, {required double top, required double height}) => Positioned(
        left: 0,
        right: 0,
        top: top,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      );

  /// A draggable grip at a lane item's edge — `onDeltaSeconds` receives
  /// the drag delta already converted from pixels to seconds. Hit area
  /// (32dp) is roughly twice the visual grip's own size, per the same
  /// touch-target research already applied once to the trim-window
  /// handle. Wrapped in the scroll-gesture lock (see `_gestureLockScroll`
  /// doc comment) so dragging it resizes instead of scrolling the
  /// timeline underneath your finger.
  Widget _edgeHandle({
    required double left,
    required double top,
    required double height,
    required ValueChanged<double> onDeltaSeconds,
  }) {
    return Positioned(
      left: left - 16,
      top: top,
      width: 32,
      height: height,
      child: Listener(
        onPointerDown: (_) => _setGestureLock(true),
        onPointerUp: (_) => _setGestureLock(false),
        onPointerCancel: (_) => _setGestureLock(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (DragUpdateDetails d) => onDeltaSeconds(d.delta.dx / _pixelsPerSecond),
          child: Center(
            child: Container(
              width: 8,
              height: height * 0.7,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: Colors.black26),
                boxShadow: const <BoxShadow>[BoxShadow(color: Colors.black45, blurRadius: 3)],
              ),
              child: const Icon(Icons.drag_indicator, size: 10, color: Colors.black45),
            ),
          ),
        ),
      ),
    );
  }

  /// Purely visual now — the ruler's own tap/drag-to-seek gesture was
  /// removed; the ScrollView's native scroll (see the `NotificationListener`
  /// in `build`) is the scrub surface for the *entire* timeline now, not
  /// just this one lane, matching the centered-playhead model.
  Widget _ruler(ColorScheme scheme, double totalSec) {
    final int lastTick = totalSec.floor();
    return Positioned(
      left: 0,
      top: 0,
      height: _Timeline._rulerHeight,
      width: totalSec * _pixelsPerSecond,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          for (int i = 0; i <= lastTick; i++)
            Positioned(
              left: i * _pixelsPerSecond - 10,
              top: 0,
              width: 20,
              child: Column(
                children: <Widget>[
                  Container(width: 1, height: 5, color: scheme.onSurfaceVariant),
                  Text("${i}s", style: TextStyle(fontSize: 8, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Greedy interval-packing: overlapping text/sticker layers get
  /// separate rows (per the spec's own ASCII diagram of two text layers
  /// stacked as distinct tracks) instead of visually colliding in one
  /// lane. Sorted by start time; an overlay goes in the first row whose
  /// last-placed item already ended by the time this one starts, else a
  /// new row.
  Map<String, int> _packOverlayRows(List<VideoOverlay> overlays) {
    final List<VideoOverlay> sorted = List<VideoOverlay>.of(overlays)
      ..sort((VideoOverlay a, VideoOverlay b) => a.startSec.compareTo(b.startSec));
    final List<Duration> rowEndTimes = <Duration>[];
    final Map<String, int> rowOf = <String, int>{};
    for (final VideoOverlay o in sorted) {
      int assigned = -1;
      for (int r = 0; r < rowEndTimes.length; r++) {
        if (rowEndTimes[r] <= o.startSec) {
          assigned = r;
          break;
        }
      }
      if (assigned == -1) {
        assigned = rowEndTimes.length;
        rowEndTimes.add(o.endSec);
      } else {
        rowEndTimes[assigned] = o.endSec;
      }
      rowOf[o.id] = assigned;
    }
    return rowOf;
  }

  @override
  Widget build(BuildContext context) {
    final double totalSec = widget.originalDuration.inMilliseconds / 1000.0;
    if (totalSec <= 0) {
      return const SizedBox.shrink();
    }
    final double trimmedSec = widget.trimmedDuration.inMilliseconds / 1000.0;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final BackgroundAudio? music = widget.bgAudio;
    double? musicLeft, musicWidth;
    Duration musicStart = Duration.zero, musicEnd = Duration.zero;
    if (music != null) {
      musicStart = music.startSec;
      final Duration musicDuration = music.duration ?? (widget.trimmedDuration - music.startSec);
      musicEnd = musicStart + musicDuration;
      musicLeft = (musicStart.inMilliseconds / 1000.0 + widget.trimStartSeconds) * _pixelsPerSecond;
      musicWidth = musicDuration.inMilliseconds / 1000.0 * _pixelsPerSecond;
    }

    final Map<String, int> overlayRow = _packOverlayRows(widget.overlays);
    final int textRows = overlayRow.values.isEmpty ? 1 : overlayRow.values.reduce(max) + 1;
    final double textLaneHeight = textRows * _Timeline._laneHeight + (textRows - 1) * _textRowGap;

    final double trimTop = _Timeline._rulerHeight + _Timeline._laneGap;
    final double speedTop = trimTop + _Timeline._trimLaneHeight + _Timeline._laneGap;
    final double musicTop = speedTop + _Timeline._laneHeight + _Timeline._laneGap;
    final double overlayTop = musicTop + _Timeline._laneHeight + _Timeline._laneGap;
    final double totalHeight = overlayTop + textLaneHeight;
    final double contentWidth = totalSec * _pixelsPerSecond;
    final double selLeft = widget.trimStartSeconds * _pixelsPerSecond;
    final double selWidth = trimmedSec * _pixelsPerSecond;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: SizedBox(
        height: totalHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: _Timeline._labelWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    height: _Timeline._rulerHeight,
                    child: ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: widget.controller,
                      builder: (BuildContext context, VideoPlayerValue value, Widget? child) => InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        onTap: () =>
                            unawaited(value.isPlaying ? widget.controller.pause() : widget.controller.play()),
                        child: Icon(
                          value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: _Timeline._laneGap),
                  SizedBox(height: _Timeline._trimLaneHeight, child: _LaneLabel("Clip", scheme)),
                  const SizedBox(height: _Timeline._laneGap),
                  SizedBox(height: _Timeline._laneHeight, child: _LaneLabel("Speed", scheme)),
                  const SizedBox(height: _Timeline._laneGap),
                  SizedBox(height: _Timeline._laneHeight, child: _LaneLabel("Music", scheme)),
                  const SizedBox(height: _Timeline._laneGap),
                  SizedBox(height: textLaneHeight, child: _LaneLabel("Text", scheme)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double viewportWidth = constraints.maxWidth;
                  return NotificationListener<ScrollNotification>(
                    onNotification: (ScrollNotification notification) {
                      if (notification is ScrollStartNotification && notification.dragDetails != null) {
                        _isUserScrubbing = true;
                      } else if (notification is ScrollUpdateNotification && _isUserScrubbing) {
                        final double sec = (notification.metrics.pixels / _pixelsPerSecond).clamp(0.0, totalSec);
                        unawaited(widget.controller.seekTo(Duration(milliseconds: (sec * 1000).round())));
                      } else if (notification is ScrollEndNotification) {
                        _isUserScrubbing = false;
                      }
                      return false;
                    },
                    child: SizedBox(
                      height: totalHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          SingleChildScrollView(
                            controller: _scrollController,
                            scrollDirection: Axis.horizontal,
                            physics: _gestureLockScroll
                                ? const NeverScrollableScrollPhysics()
                                : const AlwaysScrollableScrollPhysics(),
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: viewportWidth / 2),
                              child: SizedBox(
                                width: contentWidth,
                                height: totalHeight,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: <Widget>[
                                    // Lane backgrounds — drawn even when
                                    // empty, so every lane's own area is
                                    // visible, not just wherever
                                    // something happens to be placed.
                                    _lane(scheme, top: trimTop, height: _Timeline._trimLaneHeight),
                                    _lane(scheme, top: speedTop, height: _Timeline._laneHeight),
                                    _lane(scheme, top: musicTop, height: _Timeline._laneHeight),
                                    _lane(scheme, top: overlayTop, height: textLaneHeight),

                                    _ruler(scheme, totalSec),

                                    // Base track — real decoded frames
                                    // when the filmstrip has generated, a
                                    // plain bar otherwise (best-effort —
                                    // see _generateThumbnails' own doc
                                    // comment).
                                    if (widget.thumbnailPaths.isNotEmpty)
                                      Positioned(
                                        top: trimTop,
                                        left: 0,
                                        width: contentWidth,
                                        height: _Timeline._trimLaneHeight,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(AppRadius.sm),
                                          child: Row(
                                            children: <Widget>[
                                              for (final String path in widget.thumbnailPaths)
                                                Expanded(
                                                  child: Image.file(
                                                    File(path),
                                                    fit: BoxFit.cover,
                                                    height: _Timeline._trimLaneHeight,
                                                    errorBuilder: (_, __, ___) =>
                                                        ColoredBox(color: scheme.surfaceContainerHighest),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      )
                                    else
                                      Positioned(
                                        top: trimTop + 20,
                                        left: 0,
                                        width: contentWidth,
                                        child: Container(
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: scheme.surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                        ),
                                      ),

                                    // Trim selection — a clean filmstrip
                                    // with the EXCLUDED portions dimmed
                                    // (not a filled block over the
                                    // selected one — that read as a
                                    // permanent colored rectangle sitting
                                    // on top of the thumbnails, not a
                                    // trim control) and a thin bright
                                    // outline around what's kept. Purely
                                    // visual/non-interactive — the two
                                    // edge handles below are the only
                                    // drag surface, so the body of the
                                    // filmstrip stays free for
                                    // scroll-to-scrub.
                                    if (selLeft > 0)
                                      Positioned(
                                        left: 0,
                                        width: selLeft,
                                        top: trimTop,
                                        height: _Timeline._trimLaneHeight,
                                        child: const IgnorePointer(
                                          child: ColoredBox(color: Colors.black54),
                                        ),
                                      ),
                                    if (selLeft + selWidth < contentWidth)
                                      Positioned(
                                        left: selLeft + selWidth,
                                        width: contentWidth - selLeft - selWidth,
                                        top: trimTop,
                                        height: _Timeline._trimLaneHeight,
                                        child: const IgnorePointer(
                                          child: ColoredBox(color: Colors.black54),
                                        ),
                                      ),
                                    Positioned(
                                      left: selLeft,
                                      width: selWidth,
                                      top: trimTop,
                                      height: _Timeline._trimLaneHeight,
                                      child: IgnorePointer(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            border: Border.all(color: scheme.primary, width: 2),
                                            borderRadius: BorderRadius.circular(AppRadius.sm),
                                          ),
                                        ),
                                      ),
                                    ),
                                    _edgeHandle(
                                      left: selLeft,
                                      top: trimTop,
                                      height: _Timeline._trimLaneHeight,
                                      onDeltaSeconds: (double deltaSec) => widget.onTrimStartChanged(
                                        widget.trimStartSeconds + deltaSec,
                                      ),
                                    ),
                                    _edgeHandle(
                                      left: selLeft + selWidth,
                                      top: trimTop,
                                      height: _Timeline._trimLaneHeight,
                                      onDeltaSeconds: (double deltaSec) => widget.onTrimEndChanged(
                                        widget.trimStartSeconds + trimmedSec + deltaSec,
                                      ),
                                    ),

                                    // Speed zones, positioned relative to
                                    // the *original* clip (zone times are
                                    // relative to the trim window's own
                                    // start). Tapping the body asks
                                    // before removing; the edge handles
                                    // resize instead.
                                    for (final SpeedZone zone in widget.speedZones) ...<Widget>[
                                      Positioned(
                                        left: (zone.start.inMilliseconds / 1000.0 + widget.trimStartSeconds) *
                                            _pixelsPerSecond,
                                        width: (zone.end - zone.start).inMilliseconds / 1000.0 * _pixelsPerSecond,
                                        top: speedTop,
                                        height: _Timeline._laneHeight,
                                        child: GestureDetector(
                                          onTap: () => unawaited(_confirmRemoveZone(context, zone)),
                                          child: Container(
                                            alignment: Alignment.center,
                                            padding: const EdgeInsets.symmetric(horizontal: 3),
                                            decoration: BoxDecoration(
                                              color: scheme.primary,
                                              borderRadius: BorderRadius.circular(AppRadius.sm),
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: <Widget>[
                                                Text(
                                                  "${zone.factor}x slow-mo",
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                  overflow: TextOverflow.clip,
                                                  softWrap: false,
                                                  maxLines: 1,
                                                ),
                                                Text(
                                                  "${_Timeline._fmt(zone.start)}–${_Timeline._fmt(zone.end)}",
                                                  style: const TextStyle(color: Colors.white70, fontSize: 8),
                                                  overflow: TextOverflow.clip,
                                                  softWrap: false,
                                                  maxLines: 1,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      _edgeHandle(
                                        left: (zone.start.inMilliseconds / 1000.0 + widget.trimStartSeconds) *
                                            _pixelsPerSecond,
                                        top: speedTop,
                                        height: _Timeline._laneHeight,
                                        onDeltaSeconds: (double deltaSec) {
                                          final Duration next =
                                              zone.start + Duration(milliseconds: (deltaSec * 1000).round());
                                          final Duration clamped = next < Duration.zero
                                              ? Duration.zero
                                              : (next > zone.end - _Timeline._minZoneDuration
                                                  ? zone.end - _Timeline._minZoneDuration
                                                  : next);
                                          widget.onResizeZone(
                                            zone,
                                            SpeedZone(start: clamped, end: zone.end, factor: zone.factor),
                                          );
                                        },
                                      ),
                                      _edgeHandle(
                                        left: (zone.end.inMilliseconds / 1000.0 + widget.trimStartSeconds) *
                                            _pixelsPerSecond,
                                        top: speedTop,
                                        height: _Timeline._laneHeight,
                                        onDeltaSeconds: (double deltaSec) {
                                          final Duration next =
                                              zone.end + Duration(milliseconds: (deltaSec * 1000).round());
                                          final Duration clamped = next > widget.trimmedDuration
                                              ? widget.trimmedDuration
                                              : (next < zone.start + _Timeline._minZoneDuration
                                                  ? zone.start + _Timeline._minZoneDuration
                                                  : next);
                                          widget.onResizeZone(
                                            zone,
                                            SpeedZone(start: zone.start, end: clamped, factor: zone.factor),
                                          );
                                        },
                                      ),
                                    ],

                                    // Music bar — same shape as a speed
                                    // zone: body taps to remove, edges
                                    // drag to resize its window.
                                    if (music != null && musicLeft != null && musicWidth != null) ...<Widget>[
                                      Positioned(
                                        left: musicLeft,
                                        width: musicWidth,
                                        top: musicTop,
                                        height: _Timeline._laneHeight,
                                        child: GestureDetector(
                                          onTap: () => unawaited(_confirmRemoveMusic(context)),
                                          child: Container(
                                            alignment: Alignment.center,
                                            padding: const EdgeInsets.symmetric(horizontal: 3),
                                            decoration: BoxDecoration(
                                              color: scheme.tertiary,
                                              borderRadius: BorderRadius.circular(AppRadius.sm),
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: <Widget>[
                                                const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: <Widget>[
                                                    Icon(Icons.music_note, size: 12, color: Colors.white),
                                                    SizedBox(width: 2),
                                                    Text(
                                                      "music",
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Text(
                                                  "${_Timeline._fmt(musicStart)}–${_Timeline._fmt(musicEnd)}",
                                                  style: const TextStyle(color: Colors.white70, fontSize: 8),
                                                  overflow: TextOverflow.clip,
                                                  softWrap: false,
                                                  maxLines: 1,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      _edgeHandle(
                                        left: musicLeft,
                                        top: musicTop,
                                        height: _Timeline._laneHeight,
                                        onDeltaSeconds: (double deltaSec) {
                                          final Duration next =
                                              musicStart + Duration(milliseconds: (deltaSec * 1000).round());
                                          final Duration clamped = next < Duration.zero
                                              ? Duration.zero
                                              : (next > musicEnd - _Timeline._minZoneDuration
                                                  ? musicEnd - _Timeline._minZoneDuration
                                                  : next);
                                          widget.onResizeMusic(
                                            BackgroundAudio(
                                              filePath: music.filePath,
                                              volume: music.volume,
                                              fadeInDuration: music.fadeInDuration,
                                              fadeOutDuration: music.fadeOutDuration,
                                              startSec: clamped,
                                              duration: musicEnd - clamped,
                                            ),
                                          );
                                        },
                                      ),
                                      _edgeHandle(
                                        left: musicLeft + musicWidth,
                                        top: musicTop,
                                        height: _Timeline._laneHeight,
                                        onDeltaSeconds: (double deltaSec) {
                                          final Duration next =
                                              musicEnd + Duration(milliseconds: (deltaSec * 1000).round());
                                          final Duration clamped = next > widget.trimmedDuration
                                              ? widget.trimmedDuration
                                              : (next < musicStart + _Timeline._minZoneDuration
                                                  ? musicStart + _Timeline._minZoneDuration
                                                  : next);
                                          widget.onResizeMusic(
                                            BackgroundAudio(
                                              filePath: music.filePath,
                                              volume: music.volume,
                                              fadeInDuration: music.fadeInDuration,
                                              fadeOutDuration: music.fadeOutDuration,
                                              startSec: musicStart,
                                              duration: clamped - musicStart,
                                            ),
                                          );
                                        },
                                      ),
                                    ],

                                    // Overlay markers — a labeled chip
                                    // (the actual text, or "sticker"),
                                    // sized/positioned by real duration,
                                    // and allocated to a row (see
                                    // _packOverlayRows) so overlapping
                                    // layers don't collide visually.
                                    for (final VideoOverlay overlay in widget.overlays) ...<Widget>[
                                      Positioned(
                                        left: (overlay.startSec.inMilliseconds / 1000.0 + widget.trimStartSeconds) *
                                            _pixelsPerSecond,
                                        width: (overlay.duration.inMilliseconds / 1000.0 * _pixelsPerSecond)
                                            .clamp(40.0, 220.0),
                                        top: overlayTop +
                                            (overlayRow[overlay.id] ?? 0) *
                                                (_Timeline._laneHeight + _textRowGap),
                                        height: _Timeline._laneHeight,
                                        child: GestureDetector(
                                          onTap: () => unawaited(_confirmRemoveOverlay(context, overlay)),
                                          child: Container(
                                            alignment: Alignment.center,
                                            padding: const EdgeInsets.symmetric(horizontal: 3),
                                            decoration: BoxDecoration(
                                              color: scheme.secondary,
                                              borderRadius: BorderRadius.circular(AppRadius.sm),
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: <Widget>[
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: <Widget>[
                                                    Icon(
                                                      overlay is TextOverlay
                                                          ? Icons.text_fields
                                                          : Icons.emoji_emotions_outlined,
                                                      size: 12,
                                                      color: Colors.white,
                                                    ),
                                                    const SizedBox(width: 2),
                                                    Flexible(
                                                      child: Text(
                                                        overlay is TextOverlay ? overlay.text : "sticker",
                                                        style: const TextStyle(color: Colors.white, fontSize: 10),
                                                        overflow: TextOverflow.ellipsis,
                                                        maxLines: 1,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Text(
                                                  "${_Timeline._fmt(overlay.startSec)}–${_Timeline._fmt(overlay.endSec)}",
                                                  style: const TextStyle(color: Colors.white70, fontSize: 8),
                                                  overflow: TextOverflow.clip,
                                                  softWrap: false,
                                                  maxLines: 1,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      _edgeHandle(
                                        left: (overlay.startSec.inMilliseconds / 1000.0 + widget.trimStartSeconds) *
                                            _pixelsPerSecond,
                                        top: overlayTop +
                                            (overlayRow[overlay.id] ?? 0) *
                                                (_Timeline._laneHeight + _textRowGap),
                                        height: _Timeline._laneHeight,
                                        onDeltaSeconds: (double deltaSec) {
                                          final Duration next =
                                              overlay.startSec + Duration(milliseconds: (deltaSec * 1000).round());
                                          final Duration clamped = next < Duration.zero
                                              ? Duration.zero
                                              : (next > overlay.endSec - _Timeline._minZoneDuration
                                                  ? overlay.endSec - _Timeline._minZoneDuration
                                                  : next);
                                          widget.onResizeOverlay(
                                            overlay,
                                            _withOverlayTiming(overlay, clamped, overlay.endSec - clamped),
                                          );
                                        },
                                      ),
                                      _edgeHandle(
                                        left: (overlay.endSec.inMilliseconds / 1000.0 + widget.trimStartSeconds) *
                                            _pixelsPerSecond,
                                        top: overlayTop +
                                            (overlayRow[overlay.id] ?? 0) *
                                                (_Timeline._laneHeight + _textRowGap),
                                        height: _Timeline._laneHeight,
                                        onDeltaSeconds: (double deltaSec) {
                                          final Duration next =
                                              overlay.endSec + Duration(milliseconds: (deltaSec * 1000).round());
                                          final Duration clamped = next > widget.trimmedDuration
                                              ? widget.trimmedDuration
                                              : (next < overlay.startSec + _Timeline._minZoneDuration
                                                  ? overlay.startSec + _Timeline._minZoneDuration
                                                  : next);
                                          widget.onResizeOverlay(
                                            overlay,
                                            _withOverlayTiming(
                                              overlay,
                                              overlay.startSec,
                                              clamped - overlay.startSec,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Fixed center playhead — outside the
                          // scrollable content, so it's the timeline that
                          // moves underneath it, not the other way
                          // around.
                          Positioned(
                            left: viewportWidth / 2 - 1,
                            top: 0,
                            height: totalHeight,
                            child: const IgnorePointer(
                              child: ColoredBox(
                                color: Colors.redAccent,
                                child: SizedBox(width: 2, height: double.infinity),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rebuilds [overlay] with a new [start]/[duration], preserving every
/// other field — a plain top-level function rather than a method on the
/// sealed [VideoOverlay] hierarchy itself, since the domain model
/// (`video_project.dart`) is deliberately kept free of anything
/// UI-specific and this is only ever called from the timeline's resize
/// handles.
VideoOverlay _withOverlayTiming(VideoOverlay overlay, Duration start, Duration duration) {
  return switch (overlay) {
    TextOverlay() => TextOverlay(
        id: overlay.id,
        xPercent: overlay.xPercent,
        yPercent: overlay.yPercent,
        startSec: start,
        duration: duration,
        text: overlay.text,
        argbColor: overlay.argbColor,
        fontSize: overlay.fontSize,
        animation: overlay.animation,
        opacity: overlay.opacity,
        hasOutline: overlay.hasOutline,
        hasShadow: overlay.hasShadow,
        hasBackground: overlay.hasBackground,
      ),
    ImageOverlay() => ImageOverlay(
        id: overlay.id,
        xPercent: overlay.xPercent,
        yPercent: overlay.yPercent,
        startSec: start,
        duration: duration,
        assetPath: overlay.assetPath,
        widthPercent: overlay.widthPercent,
        rotationDegrees: overlay.rotationDegrees,
      ),
  };
}

class _LaneLabel extends StatelessWidget {
  const _LaneLabel(this.text, this.scheme);
  final String text;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _OverlayPreview extends StatelessWidget {
  const _OverlayPreview({required this.overlay, required this.previewWidth});

  final VideoOverlay overlay;
  final double previewWidth;

  @override
  Widget build(BuildContext context) {
    return switch (overlay) {
      final TextOverlay text => Opacity(
          opacity: text.opacity,
          child: Container(
            padding: text.hasBackground ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4) : null,
            decoration: text.hasBackground
                ? BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(4))
                : null,
            child: Text(
              text.text,
              style: TextStyle(
                color: Color(text.argbColor),
                fontSize: text.fontSize,
                fontWeight: FontWeight.bold,
                shadows: <Shadow>[
                  if (text.hasOutline)
                    for (final Offset o in const <Offset>[
                      Offset(-1, -1),
                      Offset(1, -1),
                      Offset(-1, 1),
                      Offset(1, 1),
                    ])
                      Shadow(color: Colors.black87, offset: o),
                  if (text.hasShadow) const Shadow(color: Colors.black54, offset: Offset(2, 2), blurRadius: 3),
                ],
              ),
            ),
          ),
        ),
      ImageOverlay(:final String assetPath, :final double widthPercent, :final double rotationDegrees) =>
        Transform.rotate(
          angle: rotationDegrees * pi / 180,
          child: SizedBox(width: previewWidth * widthPercent, child: Image.file(File(assetPath))),
        ),
    };
  }
}

final class _TimeRange {
  const _TimeRange({required this.start, required this.end});
  final Duration start;
  final Duration end;
}

/// What the sticker picker returned: a preset symbol, or "go pick a real
/// image from the gallery instead."
sealed class _StickerChoice {
  const _StickerChoice();
}

final class _StickerSymbolChoice extends _StickerChoice {
  const _StickerSymbolChoice(this.symbol);
  final String symbol;
}

final class _StickerGalleryChoice extends _StickerChoice {
  const _StickerGalleryChoice();
}

/// Preset sticker glyphs, rendered through the same drawtext/font
/// pipeline as a text overlay (not a new image-compositing path) — kept
/// to plain symbol characters within Roboto's own glyph coverage rather
/// than color emoji, which a bundled non-emoji TTF can't render.
const List<String> _stickerSymbols = <String>["★", "♥", "✓", "✗", "➤", "‼", "●", "▲", "✦", "☆"];

class _StickerPickerDialog extends StatelessWidget {
  const _StickerPickerDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Add a sticker"),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            GridView.count(
              crossAxisCount: 5,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: <Widget>[
                for (final String symbol in _stickerSymbols)
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    onTap: () => Navigator.of(context).pop(_StickerSymbolChoice(symbol)),
                    child: Center(child: Text(symbol, style: const TextStyle(fontSize: 28))),
                  ),
              ],
            ),
            const Divider(height: AppSpacing.xl),
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(const _StickerGalleryChoice()),
              icon: const Icon(Icons.image_outlined),
              label: const Text("Choose an image from gallery instead"),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
      ],
    );
  }
}

class _TimeRangeDialog extends StatefulWidget {
  const _TimeRangeDialog({required this.maxDuration});
  final Duration maxDuration;

  @override
  State<_TimeRangeDialog> createState() => _TimeRangeDialogState();
}

class _TimeRangeDialogState extends State<_TimeRangeDialog> {
  late double _start = 0;
  late double _end = widget.maxDuration.inMilliseconds / 1000.0;

  @override
  Widget build(BuildContext context) {
    final double maxSec = widget.maxDuration.inMilliseconds / 1000.0;
    return AlertDialog(
      title: const Text("When should this show?"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text("From ${_start.toStringAsFixed(1)}s to ${_end.toStringAsFixed(1)}s"),
          RangeSlider(
            values: RangeValues(_start, _end),
            max: maxSec,
            onChanged: (RangeValues v) => setState(() {
              _start = v.start;
              _end = v.end;
            }),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _TimeRange(
              start: Duration(milliseconds: (_start * 1000).round()),
              end: Duration(milliseconds: (_end * 1000).round()),
            ),
          ),
          child: const Text("OK"),
        ),
      ],
    );
  }
}

class _SpeedZoneDialog extends StatefulWidget {
  const _SpeedZoneDialog({required this.maxDuration});
  final Duration maxDuration;

  @override
  State<_SpeedZoneDialog> createState() => _SpeedZoneDialogState();
}

class _SpeedZoneDialogState extends State<_SpeedZoneDialog> {
  late double _start = 0;
  late double _end = widget.maxDuration.inMilliseconds / 1000.0;
  double _factor = 0.5;

  @override
  Widget build(BuildContext context) {
    final double maxSec = widget.maxDuration.inMilliseconds / 1000.0;
    return AlertDialog(
      title: const Text("Speed zone"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text("From ${_start.toStringAsFixed(1)}s to ${_end.toStringAsFixed(1)}s"),
          RangeSlider(
            values: RangeValues(_start, _end),
            max: maxSec,
            onChanged: (RangeValues v) => setState(() {
              _start = v.start;
              _end = v.end;
            }),
          ),
          Text("Speed: ${_factor.toStringAsFixed(2)}x${_factor < 1 ? ' (slow motion)' : ''}"),
          Slider(
            value: _factor,
            min: 0.5,
            max: 2.0,
            divisions: 6,
            onChanged: (double v) => setState(() => _factor = v),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            SpeedZone(
              start: Duration(milliseconds: (_start * 1000).round()),
              end: Duration(milliseconds: (_end * 1000).round()),
              factor: _factor,
            ),
          ),
          child: const Text("Add"),
        ),
      ],
    );
  }
}

class _TextOverlayDialog extends StatefulWidget {
  const _TextOverlayDialog({required this.id, required this.maxDuration});
  final String id;
  final Duration maxDuration;

  @override
  State<_TextOverlayDialog> createState() => _TextOverlayDialogState();
}

class _TextStyle {
  const _TextStyle(this.label, this.fontSize, this.argbColor, this.weight);
  final String label;
  final double fontSize;
  final int argbColor;
  final FontWeight weight;
}

const List<_TextStyle> _textStyles = <_TextStyle>[
  _TextStyle("Bold", 32, 0xFFFFFFFF, FontWeight.w900),
  _TextStyle("Classic", 26, 0xFFFFFFFF, FontWeight.w600),
  _TextStyle("Big", 44, 0xFFFFFFFF, FontWeight.w800),
  _TextStyle("Yellow", 30, 0xFFFFD400, FontWeight.w800),
  _TextStyle("Pink", 30, 0xFFFF2D8C, FontWeight.w800),
  _TextStyle("Small", 20, 0xFFFFFFFF, FontWeight.w600),
];

class _TextOverlayDialogState extends State<_TextOverlayDialog> {
  final TextEditingController _textController = TextEditingController();
  late double _start = 0;
  late double _end = widget.maxDuration.inMilliseconds / 1000.0;
  int _styleIndex = 0;
  TextAnimation _animation = TextAnimation.none;
  double _opacity = 1.0;
  bool _hasOutline = false;
  bool _hasShadow = false;
  bool _hasBackground = false;

  @override
  void initState() {
    super.initState();
    // The Add button's enabled state depends on this text — without a
    // listener the button never rebuilds when the user types, and only
    // seemed to "unstick" when something else (the range slider)
    // happened to trigger a setState first.
    _textController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double maxSec = widget.maxDuration.inMilliseconds / 1000.0;
    final _TextStyle style = _textStyles[_styleIndex];
    return AlertDialog(
      title: const Text("Add text"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(controller: _textController, autofocus: true, maxLength: 60),
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              color: Colors.black,
              alignment: Alignment.center,
              child: Opacity(
                opacity: _opacity,
                child: Container(
                  padding: _hasBackground ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4) : null,
                  decoration: _hasBackground
                      ? BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(4),
                        )
                      : null,
                  child: Text(
                    _textController.text.isEmpty ? "Preview" : _textController.text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(style.argbColor),
                      fontSize: style.fontSize,
                      fontWeight: style.weight,
                      shadows: <Shadow>[
                        if (_hasOutline)
                          for (final Offset o in const <Offset>[
                            Offset(-1, -1),
                            Offset(1, -1),
                            Offset(-1, 1),
                            Offset(1, 1),
                          ])
                            Shadow(color: Colors.black87, offset: o),
                        if (_hasShadow) const Shadow(color: Colors.black54, offset: Offset(2, 2), blurRadius: 3),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text("Style", style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              children: <Widget>[
                FilterChip(
                  label: const Text("Outline"),
                  selected: _hasOutline,
                  onSelected: (bool v) => setState(() => _hasOutline = v),
                ),
                FilterChip(
                  label: const Text("Shadow"),
                  selected: _hasShadow,
                  onSelected: (bool v) => setState(() => _hasShadow = v),
                ),
                FilterChip(
                  label: const Text("Background"),
                  selected: _hasBackground,
                  onSelected: (bool v) => setState(() => _hasBackground = v),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text("Opacity: ${(_opacity * 100).round()}%"),
            Slider(
              value: _opacity,
              min: 0.2,
              max: 1.0,
              onChanged: (double v) => setState(() => _opacity = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _textStyles.length,
                itemBuilder: (BuildContext context, int i) => Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ChoiceChip(
                    label: Text(_textStyles[i].label),
                    selected: _styleIndex == i,
                    onSelected: (_) => setState(() => _styleIndex = i),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text("Entrance effect", style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              children: <Widget>[
                for (final TextAnimation anim in TextAnimation.values)
                  ChoiceChip(
                    label: Text(
                      switch (anim) {
                        TextAnimation.none => "None",
                        TextAnimation.slideIn => "Slide in",
                        TextAnimation.popIn => "Pop in",
                      },
                    ),
                    selected: _animation == anim,
                    onSelected: (_) => setState(() => _animation = anim),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text("From ${_start.toStringAsFixed(1)}s to ${_end.toStringAsFixed(1)}s"),
            RangeSlider(
              values: RangeValues(_start, _end),
              max: maxSec,
              onChanged: (RangeValues v) => setState(() {
                _start = v.start;
                _end = v.end;
              }),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
        FilledButton(
          onPressed: _textController.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(
                    TextOverlay(
                      id: widget.id,
                      xPercent: 0.1,
                      yPercent: 0.1,
                      startSec: Duration(milliseconds: (_start * 1000).round()),
                      duration: Duration(milliseconds: ((_end - _start) * 1000).round()),
                      text: _textController.text.trim(),
                      argbColor: style.argbColor,
                      fontSize: style.fontSize,
                      animation: _animation,
                      opacity: _opacity,
                      hasOutline: _hasOutline,
                      hasShadow: _hasShadow,
                      hasBackground: _hasBackground,
                    ),
                  ),
          child: const Text("Add"),
        ),
      ],
    );
  }
}

class _BackgroundAudioDialog extends StatefulWidget {
  const _BackgroundAudioDialog({required this.filePath, required this.maxDuration});
  final String filePath;
  final Duration maxDuration;

  @override
  State<_BackgroundAudioDialog> createState() => _BackgroundAudioDialogState();
}

class _BackgroundAudioDialogState extends State<_BackgroundAudioDialog> {
  double _volume = 0.5;
  double _fadeIn = 1.0;
  double _fadeOut = 1.0;

  @override
  Widget build(BuildContext context) {
    final double maxFade = (widget.maxDuration.inMilliseconds / 1000.0).clamp(0, 5);
    return AlertDialog(
      title: const Text("Background music"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text("Volume: ${(_volume * 100).round()}%"),
          Slider(value: _volume, onChanged: (double v) => setState(() => _volume = v)),
          Text("Fade in: ${_fadeIn.toStringAsFixed(1)}s"),
          Slider(value: _fadeIn, max: maxFade, onChanged: (double v) => setState(() => _fadeIn = v)),
          Text("Fade out: ${_fadeOut.toStringAsFixed(1)}s"),
          Slider(value: _fadeOut, max: maxFade, onChanged: (double v) => setState(() => _fadeOut = v)),
        ],
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            BackgroundAudio(
              filePath: widget.filePath,
              volume: _volume,
              fadeInDuration: Duration(milliseconds: (_fadeIn * 1000).round()),
              fadeOutDuration: Duration(milliseconds: (_fadeOut * 1000).round()),
            ),
          ),
          child: const Text("Add"),
        ),
      ],
    );
  }
}

extension on AppColorFilter {
  String get label => switch (this) {
        AppColorFilter.none => "Original",
        AppColorFilter.warm => "Warm",
        AppColorFilter.cool => "Cool",
        AppColorFilter.blackAndWhite => "Mono",
        AppColorFilter.vintage => "Vintage",
        AppColorFilter.vivid => "Vivid",
        AppColorFilter.dramatic => "Dramatic",
      };

  /// A `ColorFilter.matrix` approximation of the FFmpeg `eq`/`hue` filter
  /// [VideoFilterGraphBuilder] applies for real at render time — close
  /// enough that what's previewed here matches what gets published,
  /// without needing to round-trip through FFmpeg just to preview a
  /// color grade.
  ColorFilter get previewFilter => switch (this) {
        AppColorFilter.none => const ColorFilter.matrix(<double>[
            1, 0, 0, 0, 0, //
            0, 1, 0, 0, 0, //
            0, 0, 1, 0, 0, //
            0, 0, 0, 1, 0, //
          ]),
        AppColorFilter.warm => const ColorFilter.matrix(<double>[
            1, 0, 0, 0, 24, //
            0, 1, 0, 0, 6, //
            0, 0, 1, 0, -18, //
            0, 0, 0, 1, 0, //
          ]),
        AppColorFilter.cool => const ColorFilter.matrix(<double>[
            1, 0, 0, 0, -18, //
            0, 1, 0, 0, 0, //
            0, 0, 1, 0, 24, //
            0, 0, 0, 1, 0, //
          ]),
        AppColorFilter.blackAndWhite => const ColorFilter.matrix(<double>[
            0.2126, 0.7152, 0.0722, 0, 0, //
            0.2126, 0.7152, 0.0722, 0, 0, //
            0.2126, 0.7152, 0.0722, 0, 0, //
            0, 0, 0, 1, 0, //
          ]),
        AppColorFilter.vintage => const ColorFilter.matrix(<double>[
            0.9, 0.1, 0.0, 0, 10, //
            0.05, 0.85, 0.05, 0, 4, //
            0.05, 0.1, 0.75, 0, -6, //
            0, 0, 0, 1, 0, //
          ]),
        AppColorFilter.vivid => const ColorFilter.matrix(<double>[
            1.35, -0.32, -0.03, 0, 0, //
            -0.10, 1.13, -0.03, 0, 0, //
            -0.10, -0.32, 1.42, 0, 0, //
            0, 0, 0, 1, 0, //
          ]),
        AppColorFilter.dramatic => const ColorFilter.matrix(<double>[
            1.25, -0.05, -0.02, 0, -25, //
            -0.05, 1.2, -0.02, 0, -25, //
            -0.02, -0.05, 1.15, 0, -30, //
            0, 0, 0, 1, 0, //
          ]),
      };
}

extension on AppVideoRotation {
  int get value => switch (this) {
        AppVideoRotation.none => 0,
        AppVideoRotation.degrees90 => 90,
        AppVideoRotation.degrees180 => 180,
        AppVideoRotation.degrees270 => 270,
      };

  int get quarterTurns => switch (this) {
        AppVideoRotation.none => 0,
        AppVideoRotation.degrees90 => 1,
        AppVideoRotation.degrees180 => 2,
        AppVideoRotation.degrees270 => 3,
      };
}
