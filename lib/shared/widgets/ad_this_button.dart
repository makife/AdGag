import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/analytics/ad_event_type.dart";
import "../../core/analytics/analytics_providers.dart";
import "../../core/router/route_paths.dart";
import "../../core/theme/app_colors.dart";
import "../../core/theme/app_spacing.dart";
import "../../features/create_ad/presentation/providers/create_ad_flow_controller.dart";
import "../../features/subjects/domain/ad_subject.dart";
import "action_rail_icon.dart";
import "count_label.dart";

/// AD THIS (CLAUDE.md section 9 — "one of the defining mechanics"). Seeds
/// [CreateAdFlowController] with the origin Ad's subject + id and jumps
/// straight to the AD tab past the subject step.
///
/// The `ad_this` analytics event fires here, at press time (intent) — the
/// authoritative *completion* signal is `ads.ad_this_count`, incremented
/// only once the remixed Ad actually reaches `ready`
/// (0009_ad_this_and_shares.sql). The two are deliberately different
/// measurements: press-through vs. follow-through.
class AdThisButton extends ConsumerWidget {
  const AdThisButton({
    required this.adId,
    required this.subjectId,
    required this.subjectDisplayName,
    required this.adThisCount,
    super.key,
  });

  final String adId;
  final String subjectId;
  final String subjectDisplayName;
  final int adThisCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: "AD THIS",
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () {
          ref.read(analyticsServiceProvider).track(adId, AdEventType.adThis);
          ref.read(createAdFlowControllerProvider.notifier).startAdThis(
                subject: AdSubject(
                  id: subjectId,
                  canonicalKey: subjectDisplayName.toLowerCase(),
                  displayName: subjectDisplayName,
                  adsCount: 0,
                ),
                inspiredByAdId: adId,
              );
          context.goTo(RoutePaths.create);
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ActionRailIcon(icon: Icons.bolt, color: AppColors.gradientOrange),
              const SizedBox(height: AppSpacing.xs),
              CountLabel(count: adThisCount, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
