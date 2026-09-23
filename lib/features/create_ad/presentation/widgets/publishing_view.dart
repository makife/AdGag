import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/router/route_paths.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../domain/create_ad_step.dart";
import "../providers/create_ad_flow_controller.dart";
import "../providers/create_ad_flow_state.dart";

/// Upload progress -> processing -> ready/failed (CLAUDE.md section 19/39).
/// One view handles [CreateAdStep.publishing]/[success]/[failure] since
/// they're really one continuous status, not three separate screens.
class PublishingView extends ConsumerWidget {
  const PublishingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CreateAdFlowState state = ref.watch(createAdFlowControllerProvider);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (state.step == CreateAdStep.publishing) ...<Widget>[
                CircularProgressIndicator(value: state.uploadProgress > 0 ? state.uploadProgress : null),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  state.uploadProgress < 1
                      ? "Uploading… ${(state.uploadProgress * 100).round()}%"
                      : "Processing…",
                ),
              ] else if (state.step == CreateAdStep.success) ...<Widget>[
                const Icon(Icons.check_circle, size: 48),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  state.processingStillPending
                      ? "Still processing — it'll show up on your profile soon."
                      : "Published!",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: () {
                    ref.read(createAdFlowControllerProvider.notifier).reset();
                    context.goTo(RoutePaths.home);
                  },
                  child: const Text("Done"),
                ),
              ] else if (state.step == CreateAdStep.failure) ...<Widget>[
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  state.errorMessage ?? "This one didn't make the campaign.",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: () => ref.read(createAdFlowControllerProvider.notifier).reset(),
                  child: const Text("Try again"),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
