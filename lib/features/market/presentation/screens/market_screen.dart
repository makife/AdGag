import "package:flutter/material.dart";

import "../../../../core/widgets/coming_soon_view.dart";

/// MARKET / DISCOVERY (CLAUDE.md section 12). Trending subjects, best/fresh
/// Ads, Daily Ad, search — implemented in Phase F.
class MarketScreen extends StatelessWidget {
  const MarketScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonView(
      title: "Market opens in Phase F",
      phaseNote: "Trending subjects, best/fresh Ads, Daily Ad and search.",
    );
  }
}
