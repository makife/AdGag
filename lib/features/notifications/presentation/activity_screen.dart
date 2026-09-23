import "package:flutter/material.dart";

import "../../../core/widgets/coming_soon_view.dart";

/// ACTIVITY tab — new followers, REVIEWS, AD THIS attribution, Daily Ad
/// results, moderation notices (CLAUDE.md section 32). Foundation lands in
/// Phase H; individual notification types arrive as their source features
/// ship (follows in Phase E, etc.).
class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonView(
      title: "Activity",
      phaseNote: "Notifications foundation lands in Phase H, fed by each feature as it ships.",
    );
  }
}
