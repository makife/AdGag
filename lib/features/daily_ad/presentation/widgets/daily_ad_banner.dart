import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/router/route_paths.dart";
import "../../../../core/theme/app_colors.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../../create_ad/presentation/providers/create_ad_flow_controller.dart";
import "../../../subjects/domain/ad_subject.dart";
import "../../../subjects/presentation/providers/subject_providers.dart";
import "../providers/daily_ad_providers.dart";

/// TODAY'S AD (CLAUDE.md section 11). Renders nothing when no challenge is
/// currently active rather than showing a stale/empty card.
class DailyAdBanner extends ConsumerWidget {
  const DailyAdBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challengeAsync = ref.watch(currentDailyChallengeProvider);

    return challengeAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (Object error, StackTrace stackTrace) => const SizedBox.shrink(),
      data: (challenge) {
        if (challenge == null) {
          return const SizedBox.shrink();
        }
        return Container(
          margin: const EdgeInsets.all(AppSpacing.lg),
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                "TODAY'S AD",
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                challenge.title,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(challenge.prompt, style: const TextStyle(color: Colors.white)),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    "${challenge.participantCount} participating",
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                    onPressed: () async {
                      final AdSubject? subject =
                          await ref.read(subjectRepositoryProvider).getSubjectById(challenge.subjectId);
                      if (subject == null || !context.mounted) {
                        return;
                      }
                      ref.read(createAdFlowControllerProvider.notifier).startDailyChallenge(
                            subject: subject,
                            dailyChallengeId: challenge.id,
                          );
                      context.goTo(RoutePaths.create);
                    },
                    child: const Text("Join"),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
