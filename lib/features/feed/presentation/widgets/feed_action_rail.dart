import "package:flutter/material.dart";

import "../../../../core/theme/app_spacing.dart";
import "../../../../shared/widgets/ad_this_button.dart";
import "../../../../shared/widgets/review_button.dart";
import "../../../../shared/widgets/share_button.dart";
import "../../../../shared/widgets/sold_button.dart";
import "../../domain/ad.dart";

/// The right-edge action column (CLAUDE.md section 6/64): SOLD, REVIEWS,
/// AD THIS, SHARE. Composes the shared design-system buttons rather than
/// reimplementing each one inline in [AdVideoCard].
class FeedActionRail extends StatelessWidget {
  const FeedActionRail({required this.ad, super.key});

  final Ad ad;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SoldButton(adId: ad.id, baseSoldCount: ad.soldCount),
        const SizedBox(height: AppSpacing.sm),
        ReviewButton(adId: ad.id, commentCount: ad.commentCount),
        const SizedBox(height: AppSpacing.sm),
        if (ad.subjectDisplayName != null)
          AdThisButton(
            adId: ad.id,
            subjectId: ad.subjectId,
            subjectDisplayName: ad.subjectDisplayName!,
            adThisCount: ad.adThisCount,
          ),
        const SizedBox(height: AppSpacing.sm),
        ShareButton(adId: ad.id, subjectDisplayName: ad.subjectDisplayName, shareCount: ad.shareCount),
      ],
    );
  }
}
