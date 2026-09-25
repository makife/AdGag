import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../domain/create_ad_step.dart";
import "../providers/create_ad_flow_controller.dart";
import "../widgets/caption_publish_step.dart";
import "../widgets/capture_step.dart";
import "../widgets/native_editor_step.dart";
import "../widgets/publishing_view.dart";
import "../widgets/subject_picker_step.dart";

/// The single creation engine's entry point (CLAUDE.md section 38): tap AD
/// -> subject -> capture -> (trim) -> caption -> publish. AD THIS and
/// Daily Ad (Phase E/F) reuse [CreateAdFlowController] the same way,
/// starting past the subject step.
///
/// The edit step is entirely native (Kotlin/Media3 CompositionPlayer on
/// Android, Swift/AVFoundation on iOS — see `native_editor_step.dart`'s
/// own doc comment for why) — there is no Flutter-side editor anymore.
class CreateAdScreen extends ConsumerWidget {
  const CreateAdScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CreateAdStep step = ref.watch(
      createAdFlowControllerProvider.select((state) => state.step),
    );

    return switch (step) {
      CreateAdStep.subject => const SubjectPickerStep(),
      CreateAdStep.capture => const CaptureStep(),
      CreateAdStep.trim => const NativeEditorStep(),
      CreateAdStep.caption => const CaptionPublishStep(),
      CreateAdStep.publishing || CreateAdStep.success || CreateAdStep.failure => const PublishingView(),
    };
  }
}
