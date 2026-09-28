import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "../../core/localization/generated/app_localizations.dart";

import "../../core/theme/app_spacing.dart";
import "../../features/comments/presentation/providers/comments_controller.dart";
import "../../features/feed/presentation/providers/reviews_panel_provider.dart";
import "action_rail_icon.dart";
import "count_label.dart";

/// REVIEWS action (CLAUDE.md section 8/64). Opens the reviews panel inside
/// the Ad's own card — the video shrinks to the top rather than being
/// covered by a sheet (see AdVideoCard / ReviewsPanel).
class ReviewButton extends ConsumerWidget {
  const ReviewButton({required this.adId, required this.commentCount, super.key});

  final String adId;
  final int commentCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).actionReviews,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => ref.read(openReviewsAdIdProvider.notifier).state = adId,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ActionRailIcon(icon: Icons.chat_bubble_outline),
              const SizedBox(height: AppSpacing.xs),
              CountLabel(count: commentCount + ref.watch(commentCountDeltaProvider(adId)), color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
