import "package:flutter/material.dart";

import "../../../../core/widgets/coming_soon_view.dart";

/// HOME / FEED (CLAUDE.md section 6). Fullscreen vertical Ad feed —
/// implemented in Phase C (video playback) / Phase E (SOLD, REVIEWS,
/// AD THIS actions) per the development order in section 52.
class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonView(
      title: "The feed is warming up",
      phaseNote: "Fullscreen Ad feed lands in Phase C (video) and Phase E (SOLD / REVIEWS / AD THIS).",
    );
  }
}
