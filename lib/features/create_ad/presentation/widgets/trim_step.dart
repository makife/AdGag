import "dart:async" show unawaited;
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:video_player/video_player.dart";

import "../../../../core/media/media_providers.dart";
import "../../../../core/media/video_editor_service.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../domain/local_video_draft.dart";
import "../../domain/video_constraints.dart";
import "../providers/create_ad_flow_controller.dart";
import "../screens/video_editor_screen.dart";

/// The creation flow's editing step (CLAUDE.md section 4/38): the fast,
/// default toolset — trim, speed, rotate, flip, remove-audio — each backed
/// by `easy_video_editor`'s native export, chained into one pass rather
/// than N intermediate re-encodes. Always shown after capture, even for a
/// clip already within [VideoConstraints], since these tools are useful
/// regardless of whether trimming is actually needed.
///
/// For speed *zones* (only part of the clip), background music, or
/// text/sticker overlays, "Advanced editor" hands off to
/// [VideoEditorScreen] — a heavier, FFmpeg-backed path kept separate so
/// the common case (most Ads need none of that) never pays for it.
class TrimStep extends ConsumerStatefulWidget {
  const TrimStep({super.key});

  @override
  ConsumerState<TrimStep> createState() => _TrimStepState();
}

class _TrimStepState extends ConsumerState<TrimStep> {
  VideoPlayerController? _controller;
  double _startSeconds = 0;
  double _speed = 1.0;
  AppVideoRotation _rotation = AppVideoRotation.none;
  AppFlipDirection _flip = AppFlipDirection.none;
  bool _removeAudio = false;
  bool _exporting = false;
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

  void _onSpeedChanged(double value) {
    setState(() => _speed = value);
    unawaited(_controller?.setPlaybackSpeed(value));
  }

  void _onRemoveAudioChanged(bool value) {
    setState(() => _removeAudio = value);
    unawaited(_controller?.setVolume(value ? 0 : 1));
  }

  void _retake() {
    ref.read(createAdFlowControllerProvider.notifier).retake();
  }

  void _openAdvancedEditor() {
    final LocalVideoDraft? draft = ref.read(createAdFlowControllerProvider).capturedDraft;
    if (draft == null) {
      return;
    }
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => VideoEditorScreen(draft: draft)),
      ),
    );
  }

  /// Undoes every edit made on this screen — back to the untouched
  /// capture, still on this screen (unlike Retake, which discards the
  /// capture itself and goes back to record/import).
  void _reset() {
    setState(() {
      _startSeconds = 0;
      _speed = 1.0;
      _rotation = AppVideoRotation.none;
      _flip = AppFlipDirection.none;
      _removeAudio = false;
    });
    final VideoPlayerController? controller = _controller;
    if (controller != null) {
      unawaited(controller.setPlaybackSpeed(1.0));
      unawaited(controller.setVolume(1));
      unawaited(controller.seekTo(Duration.zero));
    }
  }

  Future<void> _confirm() async {
    final LocalVideoDraft? draft = ref.read(createAdFlowControllerProvider).capturedDraft;
    if (draft == null) {
      return;
    }
    setState(() {
      _exporting = true;
      _error = null;
    });

    try {
      final Duration start = Duration(milliseconds: (_startSeconds * 1000).round());
      final Duration end = start + VideoConstraints.max > draft.duration
          ? draft.duration
          : start + VideoConstraints.max;
      final bool needsTrim = start > Duration.zero || end < draft.duration;

      final VideoEditRequest request = VideoEditRequest(
        sourcePath: draft.filePath,
        trimStart: start,
        trimEnd: end,
        speed: _speed,
        rotation: _rotation,
        flip: _flip,
        removeAudio: _removeAudio,
      );

      final LocalVideoDraft finalDraft;
      if (!needsTrim && !request.hasAnyEdit) {
        // Nothing was actually changed — publish the capture as-is rather
        // than paying for a no-op native re-encode.
        finalDraft = draft;
      } else {
        final String outputPath = await ref.read(videoEditorServiceProvider).apply(request);
        final Duration outputDuration =
            await ref.read(localVideoProberProvider).probeDuration(outputPath);
        finalDraft = LocalVideoDraft(filePath: outputPath, duration: outputDuration);
      }

      ref.read(createAdFlowControllerProvider.notifier).onVideoTrimmed(finalDraft);
    } catch (e) {
      setState(() => _error = "Edit failed: $e");
    } finally {
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
      appBar: AppBar(
        title: const Text("Edit your Ad"),
        actions: <Widget>[
          TextButton(
            onPressed: (!ready || _exporting) ? null : _openAdvancedEditor,
            child: const Text("Advanced"),
          ),
          TextButton(
            onPressed: _exporting ? null : _reset,
            child: const Text("Reset"),
          ),
          TextButton(
            onPressed: _exporting ? null : _retake,
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
                    ? ColoredBox(
                        color: Colors.black,
                        child: Center(
                          // RotatedBox (not Transform.rotate) so a 90/270
                          // turn actually swaps the layout size it reports
                          // to its parent — Transform.rotate only rotates
                          // visually and was overflowing this box for
                          // quarter turns on a 9:16 clip.
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
                      )
                    : const ColoredBox(
                        color: Colors.black12,
                        child: Center(child: CircularProgressIndicator()),
                      ),
              ),
              const SizedBox(height: AppSpacing.lg),

              if (ready) ...<Widget>[
                if (_maxStartSeconds > 0) ...<Widget>[
                  Text(
                    "Trim — starts at ${_startSeconds.toStringAsFixed(1)}s",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Slider(
                    value: _startSeconds.clamp(0, _maxStartSeconds),
                    max: _maxStartSeconds,
                    onChanged: (double v) {
                      setState(() => _startSeconds = v);
                      unawaited(controller.seekTo(Duration(milliseconds: (v * 1000).round())));
                    },
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Text(
                      "Already fits within ${VideoConstraints.max.inSeconds}s — nothing to trim.",
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),

                Text(
                  "Speed — ${_speed.toStringAsFixed(2)}x"
                  "${_speed < 1 ? ' (slow motion)' : _speed > 1 ? ' (fast)' : ''}",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Slider(
                  value: _speed,
                  min: 0.5,
                  max: 2.0,
                  divisions: 6,
                  onChanged: _onSpeedChanged,
                ),
                const SizedBox(height: AppSpacing.sm),

                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: _cycleRotation,
                      icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
                      label: Text(_rotation == AppVideoRotation.none ? "Rotate" : "${_rotation.value}°"),
                    ),
                    FilterChip(
                      label: const Text("Flip horizontal"),
                      selected: _flip == AppFlipDirection.horizontal,
                      onSelected: (_) => _toggleFlip(AppFlipDirection.horizontal),
                    ),
                    FilterChip(
                      label: const Text("Flip vertical"),
                      selected: _flip == AppFlipDirection.vertical,
                      onSelected: (_) => _toggleFlip(AppFlipDirection.vertical),
                    ),
                    FilterChip(
                      label: const Text("Mute"),
                      selected: _removeAudio,
                      onSelected: _onRemoveAudioChanged,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (!ready || _exporting) ? null : _confirm,
                  child: _exporting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
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
