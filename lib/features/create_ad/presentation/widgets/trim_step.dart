import "dart:async" show StreamSubscription, unawaited;
import "dart:io";
import "dart:math" show pi;

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
  double _startSeconds = 0;
  AppVideoRotation _rotation = AppVideoRotation.none;
  AppFlipDirection _flip = AppFlipDirection.none;
  bool _removeAudio = false;
  AppColorFilter _colorFilter = AppColorFilter.none;
  BackgroundAudio? _bgAudio;
  final List<SpeedZone> _speedZones = <SpeedZone>[];
  final List<VideoOverlay> _overlays = <VideoOverlay>[];

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
            setState(() {});
            unawaited(controller.setLooping(true));
            unawaited(controller.play());
            controller.addListener(_syncLivePreview);
          }
        }),
      );
    }
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _controller?.dispose().ignore();
    _musicController?.dispose().ignore();
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
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final double elapsedInTrim = controller.value.position.inMilliseconds / 1000.0 - _startSeconds;

    double desiredSpeed = 1.0;
    for (final SpeedZone zone in _speedZones) {
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
    final BackgroundAudio? bg = _bgAudio;
    if (music == null || bg == null || !music.value.isInitialized) {
      return;
    }
    final double musicStart = bg.startSec.inMilliseconds / 1000.0;
    final double musicDuration =
        (bg.duration ?? (_trimmedDuration - bg.startSec)).inMilliseconds / 1000.0;
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

  /// Creates/replaces/tears down `_musicController` to match [audio] —
  /// the single place `_bgAudio` should be written from, so the preview
  /// player never drifts out of sync with what's actually selected
  /// (direct `setState(() => _bgAudio = ...)` calls used to be scattered
  /// across the music-picker dialog and the timeline's resize/remove
  /// callbacks with no controller lifecycle attached to any of them).
  Future<void> _setBgAudio(BackgroundAudio? audio) async {
    final bool sourceChanged = _bgAudio?.filePath != audio?.filePath;
    setState(() => _bgAudio = audio);
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

  bool get _hasAnyEdit =>
      _startSeconds > 0 ||
      _rotation != AppVideoRotation.none ||
      _flip != AppFlipDirection.none ||
      _removeAudio ||
      _colorFilter != AppColorFilter.none ||
      _bgAudio != null ||
      _speedZones.isNotEmpty ||
      _overlays.isNotEmpty;

  double get _maxStartSeconds {
    final Duration? total = _controller?.value.duration;
    if (total == null) {
      return 0;
    }
    final double maxStart = total.inMilliseconds / 1000.0 - VideoConstraints.max.inSeconds;
    return maxStart < 0 ? 0 : maxStart;
  }

  Duration get _trimmedDuration {
    final Duration? total = _controller?.value.duration;
    if (total == null) {
      return Duration.zero;
    }
    final Duration start = Duration(milliseconds: (_startSeconds * 1000).round());
    final Duration end = start + VideoConstraints.max > total ? total : start + VideoConstraints.max;
    return end - start;
  }

  void _cycleRotation() {
    setState(() {
      _rotation = switch (_rotation) {
        AppVideoRotation.none => AppVideoRotation.degrees90,
        AppVideoRotation.degrees90 => AppVideoRotation.degrees180,
        AppVideoRotation.degrees180 => AppVideoRotation.degrees270,
        AppVideoRotation.degrees270 => AppVideoRotation.none,
      };
    });
  }

  void _toggleFlip(AppFlipDirection direction) {
    setState(() => _flip = _flip == direction ? AppFlipDirection.none : direction);
  }

  void _toggleRemoveAudio() {
    setState(() => _removeAudio = !_removeAudio);
    unawaited(_controller?.setVolume(_removeAudio ? 0 : 1));
  }

  void _cycleColorFilter() {
    setState(() {
      _colorFilter = switch (_colorFilter) {
        AppColorFilter.none => AppColorFilter.warm,
        AppColorFilter.warm => AppColorFilter.cool,
        AppColorFilter.cool => AppColorFilter.blackAndWhite,
        AppColorFilter.blackAndWhite => AppColorFilter.none,
      };
    });
  }

  Future<void> _addSpeedZone() async {
    final SpeedZone? zone = await showDialog<SpeedZone>(
      context: context,
      builder: (BuildContext context) => _SpeedZoneDialog(maxDuration: _trimmedDuration),
    );
    if (zone == null) {
      return;
    }
    if (_speedZones.any((SpeedZone z) => z.overlaps(zone))) {
      _showSnack("That overlaps an existing speed zone.");
      return;
    }
    setState(() => _speedZones.add(zone));
  }

  /// Drag-resize from the timeline's own edge handles (see [_Timeline]) —
  /// distinct from `_addSpeedZone`'s overlap check, since a zone shrinking
  /// or growing against its own previous bounds isn't "overlapping
  /// itself"; a stray drag past a neighboring zone is left uncorrected on
  /// purpose (rare with the zone counts this editor sees, and clamping
  /// against every sibling on every drag frame isn't worth the
  /// complexity yet).
  void _onResizeZone(SpeedZone oldZone, SpeedZone updated) {
    setState(() {
      final int index = _speedZones.indexOf(oldZone);
      if (index != -1) {
        _speedZones[index] = updated;
      }
    });
  }

  Future<void> _addTextOverlay() async {
    final TextOverlay? overlay = await showDialog<TextOverlay>(
      context: context,
      builder: (BuildContext context) => _TextOverlayDialog(id: _uuid.v4(), maxDuration: _trimmedDuration),
    );
    if (overlay != null) {
      setState(() => _overlays.add(overlay));
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
        setState(
          () => _overlays.add(
            TextOverlay(
              id: _uuid.v4(),
              xPercent: 0.4,
              yPercent: 0.3,
              startSec: range.start,
              duration: range.end - range.start,
              text: symbol,
              fontSize: 64,
            ),
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
    setState(
      () => _overlays.add(
        ImageOverlay(
          id: _uuid.v4(),
          xPercent: 0.35,
          yPercent: 0.35,
          startSec: range.start,
          duration: range.end - range.start,
          assetPath: file.path,
        ),
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
    setState(() {
      final int index = _overlays.indexWhere((VideoOverlay o) => o.id == overlay.id);
      if (index != -1) {
        _overlays[index] = updated;
      }
    });
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
  /// capture itself and goes back to record/import).
  void _reset() {
    setState(() {
      _startSeconds = 0;
      _rotation = AppVideoRotation.none;
      _flip = AppFlipDirection.none;
      _removeAudio = false;
      _colorFilter = AppColorFilter.none;
      _speedZones.clear();
      _overlays.clear();
    });
    unawaited(_controller?.setVolume(1));
    unawaited(_controller?.seekTo(Duration.zero));
    unawaited(_setBgAudio(null));
  }

  Future<void> _confirm() async {
    final LocalVideoDraft? draft = ref.read(createAdFlowControllerProvider).capturedDraft;
    if (draft == null) {
      return;
    }
    setState(() {
      _processing = true;
      _progress = 0;
      _error = null;
    });

    try {
      final Duration start = Duration(milliseconds: (_startSeconds * 1000).round());
      final Duration end = start + VideoConstraints.max > draft.duration
          ? draft.duration
          : start + VideoConstraints.max;
      final bool needsTrim = start > Duration.zero || end < draft.duration;
      final bool hasSimpleEdit = _rotation != AppVideoRotation.none ||
          _flip != AppFlipDirection.none ||
          _removeAudio;
      // Color grading has no equivalent in the fast easy_video_editor
      // pipeline (no color-filter support there), so it forces the FFmpeg
      // path the same way a speed zone or overlay does.
      final bool hasAdvancedEdit = _speedZones.isNotEmpty ||
          _overlays.isNotEmpty ||
          _colorFilter != AppColorFilter.none ||
          _bgAudio != null;

      final LocalVideoDraft finalDraft;
      if (!needsTrim && !hasSimpleEdit && !hasAdvancedEdit) {
        // Nothing was actually changed — publish the capture as-is rather
        // than paying for a no-op re-encode.
        finalDraft = draft;
      } else if (hasAdvancedEdit) {
        final VideoProject project = VideoProject(
          videoPath: draft.filePath,
          trimStart: start,
          trimEnd: end,
          speedZones: _speedZones,
          overlays: _overlays,
          rotation: _rotation,
          flip: _flip,
          removeAudio: _removeAudio,
          colorFilter: _colorFilter,
          bgAudio: _bgAudio,
        );
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
          trimStart: start,
          trimEnd: end,
          rotation: _rotation,
          flip: _flip,
          removeAudio: _removeAudio,
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
    final bool ready = controller != null && controller.value.isInitialized;

    final bool hasEdits = _hasAnyEdit;
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

    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit your Ad"),
        actions: <Widget>[
          TextButton(
            onPressed: _processing ? null : _reset,
            child: const Text("Reset"),
          ),
          TextButton(
            onPressed: _processing ? null : _retake,
            child: const Text("Retake"),
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
                                    colorFilter: _colorFilter.previewFilter,
                                    child: RotatedBox(
                                      quarterTurns: _rotation.quarterTurns,
                                      child: Transform(
                                        alignment: Alignment.center,
                                        transform: Matrix4.diagonal3Values(
                                          _flip == AppFlipDirection.horizontal ? -1 : 1,
                                          _flip == AppFlipDirection.vertical ? -1 : 1,
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
                                for (final VideoOverlay overlay in _overlays)
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
                                              onTap: () => setState(
                                                () => _overlays.removeWhere((VideoOverlay o) => o.id == overlay.id),
                                              ),
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
                        label: _rotation == AppVideoRotation.none ? "Rotate" : "${_rotation.value}°",
                        selected: _rotation != AppVideoRotation.none,
                        onTap: _cycleRotation,
                      ),
                      _ToolButton(
                        icon: Icons.flip,
                        label: "Flip H",
                        selected: _flip == AppFlipDirection.horizontal,
                        onTap: () => _toggleFlip(AppFlipDirection.horizontal),
                      ),
                      _ToolButton(
                        icon: Icons.flip,
                        label: "Flip V",
                        selected: _flip == AppFlipDirection.vertical,
                        onTap: () => _toggleFlip(AppFlipDirection.vertical),
                        iconTurns: 1,
                      ),
                      _ToolButton(
                        icon: _removeAudio ? Icons.volume_off : Icons.volume_up,
                        label: "Mute",
                        selected: _removeAudio,
                        onTap: _toggleRemoveAudio,
                      ),
                      _ToolButton(
                        icon: Icons.palette_outlined,
                        label: _colorFilter.label,
                        selected: _colorFilter != AppColorFilter.none,
                        onTap: _cycleColorFilter,
                      ),
                      _ToolButton(
                        icon: Icons.music_note_outlined,
                        label: "Music",
                        selected: _bgAudio != null,
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

                const SizedBox(height: AppSpacing.md),
                _Timeline(
                  originalDuration: controller.value.duration,
                  trimStartSeconds: _startSeconds,
                  maxTrimStartSeconds: _maxStartSeconds,
                  trimmedDuration: _trimmedDuration,
                  onTrimStartChanged: (double v) {
                    setState(() => _startSeconds = v);
                    unawaited(controller.seekTo(Duration(milliseconds: (v * 1000).round())));
                  },
                  speedZones: _speedZones,
                  overlays: _overlays,
                  bgAudio: _bgAudio,
                  onRemoveZone: (SpeedZone z) => setState(() => _speedZones.remove(z)),
                  onResizeZone: _onResizeZone,
                  onRemoveOverlay: (String id) =>
                      setState(() => _overlays.removeWhere((VideoOverlay o) => o.id == id)),
                  onResizeMusic: (BackgroundAudio updated) => unawaited(_setBgAudio(updated)),
                  onRemoveMusic: () => unawaited(_setBgAudio(null)),
                ),
                if (_maxStartSeconds == 0)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      "Already fits within ${VideoConstraints.max.inSeconds}s — nothing to trim.",
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
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

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (!ready || _processing) ? null : () => unawaited(_confirm()),
                  child: _processing
                      ? Text("Processing… ${(_progress * 100).round()}%")
                      : const Text("Continue"),
                ),
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

/// The timeline: a visibly bounded panel (a bordered/tinted [Container],
/// not empty space) with a fixed-width label column on the left naming
/// each lane ("Clip", "Speed", "Music", "Text") and, to the right, a
/// time-mapped track area per lane — a lane's background is drawn even
/// when it's empty, so it's clear that's the region a slow-mo zone or
/// music clip would occupy, not an arbitrary gap (this used to be a
/// single unlabeled Stack, which is what made added chips look like they
/// were floating in empty space with no visible boundary).
///
/// Speed-zone and music-lane items are directly drag-resizable from their
/// own left/right edge handles, in addition to tap-to-remove on the body
/// of the chip/bar. The trim window itself is still drag-to-move, as
/// before.
class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.originalDuration,
    required this.trimStartSeconds,
    required this.maxTrimStartSeconds,
    required this.trimmedDuration,
    required this.onTrimStartChanged,
    required this.speedZones,
    required this.overlays,
    required this.bgAudio,
    required this.onRemoveZone,
    required this.onResizeZone,
    required this.onRemoveOverlay,
    required this.onResizeMusic,
    required this.onRemoveMusic,
  });

  final Duration originalDuration;
  final double trimStartSeconds;
  final double maxTrimStartSeconds;
  final Duration trimmedDuration;
  final ValueChanged<double> onTrimStartChanged;
  final List<SpeedZone> speedZones;
  final List<VideoOverlay> overlays;
  final BackgroundAudio? bgAudio;
  final void Function(SpeedZone) onRemoveZone;
  final void Function(SpeedZone oldZone, SpeedZone updated) onResizeZone;
  final void Function(String) onRemoveOverlay;
  final void Function(BackgroundAudio updated) onResizeMusic;
  final VoidCallback onRemoveMusic;

  static const double _labelWidth = 52;
  static const double _trimLaneHeight = 44;
  static const double _laneHeight = 32;
  static const double _laneGap = 6;
  static const Duration _minZoneDuration = Duration(milliseconds: 300);

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
      onRemoveZone(zone);
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
      onRemoveOverlay(overlay.id);
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
      onRemoveMusic();
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

  /// A small draggable grip at a lane item's edge — `onDeltaSeconds`
  /// receives the drag delta already converted from pixels to seconds of
  /// *timeline* time, so callers never touch pixels.
  Widget _edgeHandle({
    required double left,
    required double top,
    required double height,
    required double trackWidth,
    required double totalSec,
    required ValueChanged<double> onDeltaSeconds,
  }) {
    return Positioned(
      left: left - 11,
      top: top,
      width: 22,
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (DragUpdateDetails d) => onDeltaSeconds(d.delta.dx / trackWidth * totalSec),
        child: Center(
          child: Container(
            width: 4,
            height: height * 0.6,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
              boxShadow: const <BoxShadow>[BoxShadow(color: Colors.black38, blurRadius: 2)],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double totalSec = originalDuration.inMilliseconds / 1000.0;
    if (totalSec <= 0) {
      return const SizedBox.shrink();
    }
    final double trimmedSec = trimmedDuration.inMilliseconds / 1000.0;
    final bool draggable = maxTrimStartSeconds > 0;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final double speedTop = _trimLaneHeight + _laneGap;
    final double musicTop = speedTop + _laneHeight + _laneGap;
    final double overlayTop = musicTop + _laneHeight + _laneGap;
    final double totalHeight = overlayTop + _laneHeight;

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
              width: _labelWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(height: _trimLaneHeight, child: _LaneLabel("Clip", scheme)),
                  const SizedBox(height: _laneGap),
                  SizedBox(height: _laneHeight, child: _LaneLabel("Speed", scheme)),
                  const SizedBox(height: _laneGap),
                  SizedBox(height: _laneHeight, child: _LaneLabel("Music", scheme)),
                  const SizedBox(height: _laneGap),
                  SizedBox(height: _laneHeight, child: _LaneLabel("Text", scheme)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double width = constraints.maxWidth;
                  final double selLeft = (trimStartSeconds / totalSec) * width;
                  final double selWidth = (trimmedSec / totalSec) * width;

                  final BackgroundAudio? music = bgAudio;
                  double? musicLeft, musicWidth;
                  Duration musicStart = Duration.zero, musicEnd = Duration.zero;
                  if (music != null) {
                    musicStart = music.startSec;
                    final Duration musicDuration = music.duration ?? (trimmedDuration - music.startSec);
                    musicEnd = musicStart + musicDuration;
                    musicLeft = ((musicStart.inMilliseconds / 1000.0 + trimStartSeconds) / totalSec) * width;
                    musicWidth = (musicDuration.inMilliseconds / 1000.0 / totalSec) * width;
                  }

                  return Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      // Lane backgrounds — drawn even when empty, so every
                      // lane's own area is visible rather than only
                      // appearing once something is placed in it.
                      _lane(scheme, top: 0, height: _trimLaneHeight),
                      _lane(scheme, top: speedTop, height: _laneHeight),
                      _lane(scheme, top: musicTop, height: _laneHeight),
                      _lane(scheme, top: overlayTop, height: _laneHeight),

                      // Base track — the full original clip, inside the
                      // "Clip" lane.
                      Positioned(
                        top: 20,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // Selection window — drag to move where the
                      // up-to-10s clip starts within the original. The
                      // hit area (44dp, per the platform-minimum touch
                      // target) is much taller than the visible pill
                      // (16dp).
                      Positioned(
                        left: selLeft,
                        width: selWidth,
                        top: 0,
                        height: _trimLaneHeight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragUpdate: !draggable
                              ? null
                              : (DragUpdateDetails d) {
                                  final double deltaSec = d.delta.dx / width * totalSec;
                                  onTrimStartChanged((trimStartSeconds + deltaSec).clamp(0, maxTrimStartSeconds));
                                },
                          child: Center(
                            child: Container(
                              height: 16,
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.3),
                                border: Border.all(color: scheme.primary, width: 2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Speed zones, positioned relative to the
                      // *original* clip (zone times are relative to the
                      // trim window's own start). Tapping the body asks
                      // before removing; the edge handles resize instead.
                      for (final SpeedZone zone in speedZones) ...<Widget>[
                        Positioned(
                          left: ((zone.start.inMilliseconds / 1000.0 + trimStartSeconds) / totalSec) * width,
                          width: ((zone.end - zone.start).inMilliseconds / 1000.0 / totalSec) * width,
                          top: speedTop,
                          height: _laneHeight,
                          child: GestureDetector(
                            onTap: () => unawaited(_confirmRemoveZone(context, zone)),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Text(
                                "${zone.factor}x slow-mo",
                                style:
                                    const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                                overflow: TextOverflow.clip,
                                softWrap: false,
                              ),
                            ),
                          ),
                        ),
                        _edgeHandle(
                          left: ((zone.start.inMilliseconds / 1000.0 + trimStartSeconds) / totalSec) * width,
                          top: speedTop,
                          height: _laneHeight,
                          trackWidth: width,
                          totalSec: totalSec,
                          onDeltaSeconds: (double deltaSec) {
                            final Duration next = zone.start + Duration(milliseconds: (deltaSec * 1000).round());
                            final Duration clamped = next < Duration.zero
                                ? Duration.zero
                                : (next > zone.end - _minZoneDuration ? zone.end - _minZoneDuration : next);
                            onResizeZone(zone, SpeedZone(start: clamped, end: zone.end, factor: zone.factor));
                          },
                        ),
                        _edgeHandle(
                          left: ((zone.end.inMilliseconds / 1000.0 + trimStartSeconds) / totalSec) * width,
                          top: speedTop,
                          height: _laneHeight,
                          trackWidth: width,
                          totalSec: totalSec,
                          onDeltaSeconds: (double deltaSec) {
                            final Duration next = zone.end + Duration(milliseconds: (deltaSec * 1000).round());
                            final Duration clamped = next > trimmedDuration
                                ? trimmedDuration
                                : (next < zone.start + _minZoneDuration ? zone.start + _minZoneDuration : next);
                            onResizeZone(zone, SpeedZone(start: zone.start, end: clamped, factor: zone.factor));
                          },
                        ),
                      ],

                      // Music bar — same shape as a speed zone: body taps
                      // to remove, edges drag to resize its window.
                      if (music != null && musicLeft != null && musicWidth != null) ...<Widget>[
                        Positioned(
                          left: musicLeft,
                          width: musicWidth,
                          top: musicTop,
                          height: _laneHeight,
                          child: GestureDetector(
                            onTap: () => unawaited(_confirmRemoveMusic(context)),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: scheme.tertiary,
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(Icons.music_note, size: 14, color: Colors.white),
                                  SizedBox(width: 3),
                                  Text(
                                    "music",
                                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        _edgeHandle(
                          left: musicLeft,
                          top: musicTop,
                          height: _laneHeight,
                          trackWidth: width,
                          totalSec: totalSec,
                          onDeltaSeconds: (double deltaSec) {
                            final Duration next = musicStart + Duration(milliseconds: (deltaSec * 1000).round());
                            final Duration clamped = next < Duration.zero
                                ? Duration.zero
                                : (next > musicEnd - _minZoneDuration ? musicEnd - _minZoneDuration : next);
                            onResizeMusic(
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
                          height: _laneHeight,
                          trackWidth: width,
                          totalSec: totalSec,
                          onDeltaSeconds: (double deltaSec) {
                            final Duration next = musicEnd + Duration(milliseconds: (deltaSec * 1000).round());
                            final Duration clamped = next > trimmedDuration
                                ? trimmedDuration
                                : (next < musicStart + _minZoneDuration ? musicStart + _minZoneDuration : next);
                            onResizeMusic(
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

                      // Overlay markers — a labeled chip (the actual
                      // text, or "sticker"), not a bare small icon with
                      // no context.
                      for (final VideoOverlay overlay in overlays)
                        Positioned(
                          left: ((overlay.startSec.inMilliseconds / 1000.0 + trimStartSeconds) / totalSec) * width,
                          top: overlayTop,
                          height: _laneHeight,
                          child: GestureDetector(
                            onTap: () => unawaited(_confirmRemoveOverlay(context, overlay)),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 110),
                              child: Container(
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                                decoration: BoxDecoration(
                                  color: scheme.secondary,
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(
                                      overlay is TextOverlay ? Icons.text_fields : Icons.emoji_emotions_outlined,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        overlay is TextOverlay ? overlay.text : "sticker",
                                        style: const TextStyle(color: Colors.white, fontSize: 11),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
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
      TextOverlay(:final String text, :final int argbColor, :final double fontSize) => Text(
          text,
          style: TextStyle(color: Color(argbColor), fontSize: fontSize, fontWeight: FontWeight.bold),
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
              child: Text(
                _textController.text.isEmpty ? "Preview" : _textController.text,
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(style.argbColor), fontSize: style.fontSize, fontWeight: style.weight),
              ),
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
        AppColorFilter.none => "Filter",
        AppColorFilter.warm => "Warm",
        AppColorFilter.cool => "Cool",
        AppColorFilter.blackAndWhite => "B&W",
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
