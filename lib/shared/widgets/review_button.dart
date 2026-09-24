import "dart:async" show unawaited;

import "package:flutter/material.dart";

import "../../core/theme/app_spacing.dart";
import "../../features/comments/presentation/widgets/reviews_sheet.dart";
import "action_rail_icon.dart";
import "count_label.dart";

/// REVIEWS action (CLAUDE.md section 8/64). Opens [ReviewsSheet].
class ReviewButton extends StatelessWidget {
  const ReviewButton({required this.adId, required this.commentCount, super.key});

  final String adId;
  final int commentCount;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: "Reviews",
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => unawaited(
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            builder: (BuildContext context) => ReviewsSheet(adId: adId),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ActionRailIcon(icon: Icons.chat_bubble_outline),
              const SizedBox(height: AppSpacing.xs),
              CountLabel(count: commentCount, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
