import "dart:async" show unawaited;
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:video_player/video_player.dart";

import "../../../../core/theme/app_spacing.dart";
import "../providers/create_ad_flow_controller.dart";
import "../providers/create_ad_flow_state.dart";

class CaptionPublishStep extends ConsumerStatefulWidget {
  const CaptionPublishStep({super.key});

  @override
  ConsumerState<CaptionPublishStep> createState() => _CaptionPublishStepState();
}

class _CaptionPublishStepState extends ConsumerState<CaptionPublishStep> {
  VideoPlayerController? _preview;

  @override
  void initState() {
    super.initState();
    final String? path = ref.read(createAdFlowControllerProvider).finalDraft?.filePath;
    if (path != null) {
      final VideoPlayerController controller = VideoPlayerController.file(File(path));
      _preview = controller;
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
    _preview?.dispose().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CreateAdFlowState state = ref.watch(createAdFlowControllerProvider);
    final VideoPlayerController? preview = _preview;
    final bool previewReady = preview != null && preview.value.isInitialized;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Preview & publish"),
        actions: <Widget>[
          TextButton(
            onPressed: () => ref.read(createAdFlowControllerProvider.notifier).retake(),
            child: const Text("Retake"),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: <Widget>[
              Expanded(
                child: previewReady
                    ? AspectRatio(aspectRatio: preview.value.aspectRatio, child: VideoPlayer(preview))
                    : const Center(child: CircularProgressIndicator()),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                maxLength: 150,
                maxLines: 2,
                decoration: const InputDecoration(hintText: "Add a caption…"),
                onChanged: (String value) =>
                    ref.read(createAdFlowControllerProvider.notifier).setCaption(value),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: state.finalDraft == null
                      ? null
                      : () => unawaited(ref.read(createAdFlowControllerProvider.notifier).publish()),
                  child: const Text("Publish"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
