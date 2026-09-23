import "dart:async" show unawaited;

import "package:flutter/material.dart";

import "../../core/router/route_paths.dart";

/// Tappable `SOCK™`-style subject label (CLAUDE.md section 3/6/10/64).
/// Navigates to the AdSubject page — the organizing primitive is the
/// subject, not a hashtag, so this is a real navigation target, not just
/// styled text.
class SubjectBadge extends StatelessWidget {
  const SubjectBadge({required this.subjectId, required this.displayName, super.key});

  final String subjectId;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => unawaited(context.pushTo(RoutePaths.subjectOf(subjectId))),
      child: Text(
        "${displayName.toUpperCase()}™",
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
      ),
    );
  }
}
