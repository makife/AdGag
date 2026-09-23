import "package:flutter/material.dart";

import "../theme/app_spacing.dart";

/// Placeholder for a tab/screen not yet built in the current development
/// phase (see CLAUDE.md section 52 — DEVELOPMENT ORDER). Used so the
/// navigation shell is fully wired and testable in Phase A even though
/// feed/market/create/profile content lands in later phases.
class ComingSoonView extends StatelessWidget {
  const ComingSoonView({required this.title, required this.phaseNote, super.key});

  final String title;
  final String phaseNote;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.sm),
              Text(
                phaseNote,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
