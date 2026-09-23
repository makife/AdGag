import "dart:async" show StreamSubscription, unawaited;
import "dart:io";

import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:image_picker/image_picker.dart";
import "package:uuid/uuid.dart";
import "package:video_player/video_player.dart";

import "../../../../core/media/media_providers.dart";
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
          }
        }),
      );
    }
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _controller?.dispose().ignore();
    super.dispose();
  }

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

  Future<void> _addTextOverlay() async {
    final TextOverlay? overlay = await showDialog<TextOverlay>(
      context: context,
      builder: (BuildContext context) => _TextOverlayDialog(id: _uuid.v4(), maxDuration: _trimmedDuration),
    );
    if (overlay != null) {
      setState(() => _overlays.add(overlay));
    }
  }

  Future<void> _addImageOverlay() async {
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
      setState(() => _bgAudio = audio);
    }
  }

  void _onOverlayDrag(VideoOverlay overlay, DragUpdateDetails details, Size previewSize) {
    final double dx = details.delta.dx / previewSize.width;
    final double dy = details.delta.dy / previewSize.height;
    final double nextX = (overlay.xPercent + dx).clamp(0.0, 1.0);
    final double nextY = (overlay.yPercent + dy).clamp(0.0, 1.0);

    final VideoOverlay moved = switch (overlay) {
      TextOverlay() => TextOverlay(
          id: overlay.id,
          xPercent: nextX,
          yPercent: nextY,
          startSec: overlay.startSec,
          duration: overlay.duration,
          text: overlay.text,
          argbColor: overlay.argbColor,
          fontSize: overlay.fontSize,
        ),
      ImageOverlay() => ImageOverlay(
          id: overlay.id,
          xPercent: nextX,
          yPercent: nextY,
          startSec: overlay.startSec,
          duration: overlay.duration,
          assetPath: overlay.assetPath,
          widthPercent: overlay.widthPercent,
        ),
    };
    setState(() {
      final int index = _overlays.indexWhere((VideoOverlay o) => o.id == overlay.id);
      if (index != -1) {
        _overlays[index] = moved;
      }
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _retake() {
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
      _bgAudio = null;
      _speedZones.clear();
      _overlays.clear();
    });
    unawaited(_controller?.setVolume(1));
    unawaited(_controller?.seekTo(Duration.zero));
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
                                      onPanUpdate: (DragUpdateDetails d) =>
                                          _onOverlayDrag(overlay, d, previewSize),
                                      onLongPress: () =>
                                          setState(() => _overlays.removeWhere((VideoOverlay o) => o.id == overlay.id)),
                                      child: _OverlayPreview(overlay: overlay),
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
                        onTap: () => unawaited(_addImageOverlay()),
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
                  onRemoveZone: (SpeedZone z) => setState(() => _speedZones.remove(z)),
                  onRemoveOverlay: (String id) =>
                      setState(() => _overlays.removeWhere((VideoOverlay o) => o.id == id)),
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

/// The timeline: a base track spanning the *original* captured clip, a
/// draggable highlighted window showing which up-to-10s slice is
/// selected (replaces what used to be a separate "Trim" slider — trim IS
/// the timeline, not an extra control above it), and — inside that
/// window — speed zones as colored segments and overlay markers, both
/// positioned by actual time fraction and tap-to-remove. Deliberately
/// not resizable-by-dragging-edges for zones/overlays yet — see
/// TrimStep's own doc comment for that scope note; the trim window
/// itself IS drag-to-move, which is the piece that used to be a
/// disconnected slider.
class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.originalDuration,
    required this.trimStartSeconds,
    required this.maxTrimStartSeconds,
    required this.trimmedDuration,
    required this.onTrimStartChanged,
    required this.speedZones,
    required this.overlays,
    required this.onRemoveZone,
    required this.onRemoveOverlay,
  });

  final Duration originalDuration;
  final double trimStartSeconds;
  final double maxTrimStartSeconds;
  final Duration trimmedDuration;
  final ValueChanged<double> onTrimStartChanged;
  final List<SpeedZone> speedZones;
  final List<VideoOverlay> overlays;
  final void Function(SpeedZone) onRemoveZone;
  final void Function(String) onRemoveOverlay;

  @override
  Widget build(BuildContext context) {
    final double totalSec = originalDuration.inMilliseconds / 1000.0;
    if (totalSec <= 0) {
      return const SizedBox.shrink();
    }
    final double trimmedSec = trimmedDuration.inMilliseconds / 1000.0;
    final bool draggable = maxTrimStartSeconds > 0;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 76,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = constraints.maxWidth;
          final double selLeft = (trimStartSeconds / totalSec) * width;
          final double selWidth = (trimmedSec / totalSec) * width;

          return Stack(
            children: <Widget>[
              // Base track — the full original clip.
              Positioned(
                top: 18,
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
              // Selection window — drag to move where the up-to-10s clip
              // starts within the original.
              Positioned(
                left: selLeft,
                width: selWidth,
                top: 12,
                child: GestureDetector(
                  onHorizontalDragUpdate: !draggable
                      ? null
                      : (DragUpdateDetails d) {
                          final double deltaSec = d.delta.dx / width * totalSec;
                          onTrimStartChanged((trimStartSeconds + deltaSec).clamp(0, maxTrimStartSeconds));
                        },
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
              // Speed zones, positioned relative to the *original* clip
              // (zone times are relative to the trim window's own start).
              for (final SpeedZone zone in speedZones)
                Positioned(
                  left: ((zone.start.inMilliseconds / 1000.0 + trimStartSeconds) / totalSec) * width,
                  width: ((zone.end - zone.start).inMilliseconds / 1000.0 / totalSec) * width,
                  top: 36,
                  child: GestureDetector(
                    onTap: () => onRemoveZone(zone),
                    child: Tooltip(
                      message: "${zone.factor}x — tap to remove",
                      child: Container(
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          "${zone.factor}x",
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ),
              for (final VideoOverlay overlay in overlays)
                Positioned(
                  left:
                      ((overlay.startSec.inMilliseconds / 1000.0 + trimStartSeconds) / totalSec) * width - 8,
                  top: 58,
                  child: GestureDetector(
                    onTap: () => onRemoveOverlay(overlay.id),
                    child: Tooltip(
                      message: "tap to remove",
                      child: Icon(
                        overlay is TextOverlay ? Icons.text_fields : Icons.emoji_emotions_outlined,
                        size: 16,
                        color: scheme.secondary,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _OverlayPreview extends StatelessWidget {
  const _OverlayPreview({required this.overlay});

  final VideoOverlay overlay;

  @override
  Widget build(BuildContext context) {
    return switch (overlay) {
      TextOverlay(:final String text, :final int argbColor, :final double fontSize) => Text(
          text,
          style: TextStyle(color: Color(argbColor), fontSize: fontSize, fontWeight: FontWeight.bold),
        ),
      ImageOverlay(:final String assetPath) => SizedBox(width: 80, child: Image.file(File(assetPath))),
    };
  }
}

final class _TimeRange {
  const _TimeRange({required this.start, required this.end});
  final Duration start;
  final Duration end;
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

class _TextOverlayDialogState extends State<_TextOverlayDialog> {
  final TextEditingController _textController = TextEditingController();
  late double _start = 0;
  late double _end = widget.maxDuration.inMilliseconds / 1000.0;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double maxSec = widget.maxDuration.inMilliseconds / 1000.0;
    return AlertDialog(
      title: const Text("Add text"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(controller: _textController, autofocus: true, maxLength: 60),
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
