import "dart:async" show unawaited;

import "package:flutter/material.dart";

import "../../core/router/route_paths.dart";
import "../../core/theme/app_colors.dart";
import "../../core/theme/app_spacing.dart";

/// Tappable `SOCK™`-style subject label (CLAUDE.md section 3/6/10/64).
/// Navigates to the AdSubject page — the organizing primitive is the
/// subject, not a hashtag, so this is a real navigation target, not just
/// styled text.
///
/// Rendered as an actual pill/badge (dark chip + a brand-gradient accent
/// dot), not plain white text — stacked directly above [CreatorHeader]'s
/// plain `@username`, two same-color same-weight text rows were too easy
/// to mis-tap (the subject badge and the nickname were visually
/// indistinguishable at a glance).
class SubjectBadge extends StatelessWidget {
  const SubjectBadge({required this.subjectId, required this.displayName, super.key});

  final String subjectId;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => unawaited(context.pushTo(RoutePaths.subjectOf(subjectId))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.darkOverlayScrim,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(gradient: AppColors.brandGradient, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              "${displayName.toUpperCase()}™",
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
