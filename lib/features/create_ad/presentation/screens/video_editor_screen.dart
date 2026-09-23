import "dart:async" show StreamSubscription, unawaited;
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:image_picker/image_picker.dart";
import "package:uuid/uuid.dart";
import "package:video_player/video_player.dart";

import "../../../../core/media/media_providers.dart";
import "../../../../core/media/video_export_service.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../domain/local_video_draft.dart";
import "../../domain/video_constraints.dart";
import "../../domain/video_project.dart";
import "../providers/create_ad_flow_controller.dart";

/// The comprehensive timeline editor: speed zones (slow motion / fast
/// forward across a chosen window) and timed text/image overlays,
/// draggable to reposition on the preview — everything [VideoProject]
/// models, rendered by [FfmpegVideoExportService] in one export pass.
/// Background music is modeled (`VideoProject.bgAudio`) and the export
/// pipeline mixes it in correctly, but there's no "pick a file" entry
/// point wired up yet — see the note near `_BackgroundAudioDialog`'s old
/// location for why.
///
/// Reached from the simple editor ([TrimStep]) via an explicit "Advanced
/// editor" action rather than replacing it — the simple trim/speed/rotate
/// path (`easy_video_editor`, no FFmpeg) stays the fast default for the
/// common case that doesn't need a multi-track timeline at all.
///
/// Scope note: this deliberately doesn't implement a draggable/resizable
/// multi-track timeline widget (colored handles you drag to resize a
/// zone) — zones/overlays are added via a short dialog and shown as
/// removable chips instead. The underlying [VideoProject]/export
/// pipeline doesn't care how a zone was created, so that visual polish
/// can be added later without touching the model, the filter-graph
/// builder, or the export service.
class VideoEditorScreen extends ConsumerStatefulWidget {
  const VideoEditorScreen({required this.draft, super.key});

  final LocalVideoDraft draft;

  @override
  ConsumerState<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends ConsumerState<VideoEditorScreen> {
  static const Uuid _uuid = Uuid();

  VideoPlayerController? _controller;
  late VideoProject _project;
  bool _exporting = false;
  double _exportProgress = 0;
  StreamSubscription<double>? _progressSub;
  String? _error;

  @override
  void initState() {
    super.initState();
    final Duration cappedEnd =
        widget.draft.duration > VideoConstraints.max ? VideoConstraints.max : widget.draft.duration;
    _project = VideoProject(videoPath: widget.draft.filePath, trimStart: Duration.zero, trimEnd: cappedEnd);

    final VideoPlayerController controller = VideoPlayerController.file(File(widget.draft.filePath));
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

  @override
  void dispose() {
    _progressSub?.cancel();
    _controller?.dispose().ignore();
    super.dispose();
  }

  Future<void> _addSpeedZone() async {
    final SpeedZone? zone = await showDialog<SpeedZone>(
      context: context,
      builder: (BuildContext context) => _SpeedZoneDialog(maxDuration: _project.trimmedDuration),
    );
    if (zone == null) {
      return;
    }
    try {
      setState(() => _project = _project.withSpeedZone(zone));
    } on ArgumentError catch (e) {
      _showSnack("${e.message}");
    }
  }

  Future<void> _addTextOverlay() async {
    final TextOverlay? overlay = await showDialog<TextOverlay>(
      context: context,
      builder: (BuildContext context) =>
          _TextOverlayDialog(id: _uuid.v4(), maxDuration: _project.trimmedDuration),
    );
    if (overlay != null) {
      setState(() => _project = _project.withOverlay(overlay));
    }
  }

  Future<void> _addImageOverlay() async {
    final XFile? file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (file == null || !mounted) {
      return;
    }
    final _TimeRange? range = await showDialog<_TimeRange>(
      context: context,
      builder: (BuildContext context) => _TimeRangeDialog(maxDuration: _project.trimmedDuration),
    );
    if (range == null) {
      return;
    }
    setState(
      () => _project = _project.withOverlay(
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
      _project = _project.withoutOverlay(overlay.id).withOverlay(moved);
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _error = null;
      _exportProgress = 0;
    });

    final VideoExportService service = ref.read(videoExportServiceProvider);
    _progressSub = service.progress.listen((double p) {
      if (mounted) {
        setState(() => _exportProgress = p);
      }
    });

    try {
      final String outputPath = await service.export(_project);
      final Duration outputDuration = await ref.read(localVideoProberProvider).probeDuration(outputPath);
      ref.read(createAdFlowControllerProvider.notifier).onVideoTrimmed(
            LocalVideoDraft(filePath: outputPath, duration: outputDuration),
          );
    } catch (e) {
      setState(() => _error = "Export failed: $e");
    } finally {
      await _progressSub?.cancel();
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? controller = _controller;
    final bool ready = controller != null && controller.value.isInitialized;

    return Scaffold(
      appBar: AppBar(title: const Text("Advanced editor")),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
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
                                child: AspectRatio(
                                  aspectRatio: controller.value.aspectRatio,
                                  child: VideoPlayer(controller),
                                ),
                              ),
                              for (final VideoOverlay overlay in _project.overlays)
                                Positioned(
                                  left: overlay.xPercent * previewSize.width,
                                  top: overlay.yPercent * previewSize.height,
                                  child: GestureDetector(
                                    onPanUpdate: (DragUpdateDetails d) => _onOverlayDrag(overlay, d, previewSize),
                                    onLongPress: () => setState(
                                      () => _project = _project.withoutOverlay(overlay.id),
                                    ),
                                    child: _OverlayPreview(overlay: overlay),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    )
                  : const ColoredBox(color: Colors.black12, child: Center(child: CircularProgressIndicator())),
            ),
            if (_project.speedZones.isNotEmpty || _project.overlays.isNotEmpty || _project.bgAudio != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: <Widget>[
                    for (final SpeedZone zone in _project.speedZones)
                      InputChip(
                        label: Text("${zone.factor}x @${zone.start.inSeconds}-${zone.end.inSeconds}s"),
                        onDeleted: () => setState(() => _project = _project.withoutSpeedZone(zone)),
                      ),
                    for (final VideoOverlay overlay in _project.overlays)
                      InputChip(
                        label: Text(overlay is TextOverlay ? "“${overlay.text}”" : "sticker"),
                        onDeleted: () => setState(() => _project = _project.withoutOverlay(overlay.id)),
                      ),
                  ],
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (_exporting)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                child: LinearProgressIndicator(value: _exportProgress > 0 ? _exportProgress : null),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
              child: Column(
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: <Widget>[
                      IconButton(
                        onPressed: _exporting ? null : () => unawaited(_addSpeedZone()),
                        icon: const Icon(Icons.slow_motion_video_outlined),
                        tooltip: "Slow-mo / speed",
                      ),
                      IconButton(
                        onPressed: _exporting ? null : () => unawaited(_addTextOverlay()),
                        icon: const Icon(Icons.text_fields),
                        tooltip: "Add text",
                      ),
                      IconButton(
                        onPressed: _exporting ? null : () => unawaited(_addImageOverlay()),
                        icon: const Icon(Icons.emoji_emotions_outlined),
                        tooltip: "Add sticker",
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: (!ready || _exporting) ? null : () => unawaited(_export()),
                      child: _exporting
                          ? Text("Exporting… ${(_exportProgress * 100).round()}%")
                          : const Text("Export"),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
      ImageOverlay(:final String assetPath) => SizedBox(
          width: 80,
          child: Image.file(File(assetPath)),
        ),
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

// Background-music picking UI is deliberately not wired here — see the
// VideoEditorScreen doc comment / CLAUDE.md checkpoint for why
// (file_picker's Android build conflicted with the other native plugins
// already fighting for Kotlin Gradle Plugin application in this project,
// and adding a second unstable native dependency in the same session as
// FFmpeg wasn't worth the risk). VideoProject.bgAudio and the filter-graph
// builder's amix/afade handling are fully implemented and ready — only
// the "pick a file" entry point is missing.
