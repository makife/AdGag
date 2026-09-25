import "dart:io" show Platform;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../domain/create_ad_step.dart";
import "../providers/create_ad_flow_controller.dart";
import "../widgets/caption_publish_step.dart";
import "../widgets/capture_step.dart";
import "../widgets/native_editor_step.dart";
import "../widgets/publishing_view.dart";
import "../widgets/subject_picker_step.dart";
import "../widgets/trim_step.dart";

/// The single creation engine's entry point (CLAUDE.md section 38): tap AD
/// -> subject -> capture -> (trim) -> caption -> publish. AD THIS and
/// Daily Ad (Phase E/F) reuse [CreateAdFlowController] the same way,
/// starting past the subject step.
class CreateAdScreen extends ConsumerWidget {
  const CreateAdScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CreateAdStep step = ref.watch(
      createAdFlowControllerProvider.select((state) => state.step),
    );
    // The native editor (Kotlin/Media3 on Android, Swift/AVFoundation on
    // iOS — see native_editor_step.dart) is the real editing entry point
    // now, not a hidden debug-menu option: pressing AD and capturing a
    // clip goes straight into it. useClassicEditorProvider is the escape
    // hatch if the native side fails (see NativeEditorStep's own "Use
    // classic editor instead" button) — TrimStep remains fully intact
    // and reachable, never deleted, so a native-side bug can never fully
    // block publishing.
    final bool useNativeEditor =
        (Platform.isAndroid || Platform.isIOS) && !ref.watch(useClassicEditorProvider);

    return switch (step) {
      CreateAdStep.subject => const SubjectPickerStep(),
      CreateAdStep.capture => const CaptureStep(),
      CreateAdStep.trim => useNativeEditor ? const NativeEditorStep() : const TrimStep(),
      CreateAdStep.caption => const CaptionPublishStep(),
      CreateAdStep.publishing || CreateAdStep.success || CreateAdStep.failure => const PublishingView(),
    };
  }
}
