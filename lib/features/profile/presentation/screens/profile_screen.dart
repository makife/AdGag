import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/theme/app_spacing.dart";
import "../../../auth/presentation/providers/auth_providers.dart";

/// PROFILE (CLAUDE.md section 13). Full grid/stats land in Phase E/F; for
/// Phase A this proves the auth -> profile round trip (username/display
/// name pulled from the `profiles` row) and provides sign-out so the auth
/// flow is fully testable end to end.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUserAsync = ref.watch(currentAppUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text("Profile")),
      body: appUserAsync.when(
        data: (user) => Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(user?.displayName ?? "—", style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xs),
              Text("@${user?.username ?? ''}", style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.xxl),
              OutlinedButton(
                onPressed: () => unawaited(ref.read(authControllerProvider.notifier).signOut()),
                child: const Text("Sign out"),
              ),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => Center(child: Text("$error")),
      ),
    );
  }
}
