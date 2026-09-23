import "dart:async" show unawaited;
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:video_player/video_player.dart";

import "../../../../core/media/media_providers.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../domain/local_video_draft.dart";
import "../../domain/video_constraints.dart";
import "../providers/create_ad_flow_controller.dart";
import "../providers/create_ad_flow_state.dart";

/// Deliberately the simplest possible trim interaction (CLAUDE.md section
/// 4: "Editing must remain intentionally lightweight"): pick where a
/// fixed 10-second window starts, rather than a full dual-handle range
/// editor. Only shown when the captured/imported clip is longer than
/// [VideoConstraints.max].
class TrimStep extends ConsumerStatefulWidget {
  const TrimStep({super.key});

  @override
  ConsumerState<TrimStep> createState() => _TrimStepState();
}

class _TrimStepState extends ConsumerState<TrimStep> {
  VideoPlayerController? _controller;
  double _startSeconds = 0;
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

      final String outputPath = await ref.read(videoTrimmerProvider).trim(
            sourcePath: draft.filePath,
            start: start,
            end: end,
          );
      final Duration trimmedDuration =
          await ref.read(localVideoProberProvider).probeDuration(outputPath);

      ref.read(createAdFlowControllerProvider.notifier).onVideoTrimmed(
            LocalVideoDraft(filePath: outputPath, duration: trimmedDuration),
          );
    } catch (e) {
      setState(() => _error = "Trim failed: $e");
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
      appBar: AppBar(title: const Text("Pick your 10 seconds")),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: <Widget>[
            Expanded(
              child: ready
                  ? AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (ready) ...<Widget>[
              Text(
                "Starts at ${_startSeconds.toStringAsFixed(1)}s",
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
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            FilledButton(
              onPressed: (!ready || _exporting) ? null : _confirm,
              child: _exporting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text("Use this clip"),
            ),
          ],
        ),
      ),
    );
  }
}
