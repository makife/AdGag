import "package:flutter/material.dart";

import "../../../../core/widgets/coming_soon_view.dart";

/// The central AD creation flow (CLAUDE.md section 38): choose subject ->
/// record/import -> trim -> caption -> preview -> publish. Implemented in
/// Phase D, reused as-is for AD THIS and Daily Ad entry points.
class CreateAdScreen extends StatelessWidget {
  const CreateAdScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonView(
      title: "Creation engine lands in Phase D",
      phaseNote: "Record/import, 10s trim, subject, caption, publish — one engine reused by AD THIS and Daily Ad.",
    );
  }
}
