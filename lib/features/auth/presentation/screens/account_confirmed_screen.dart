import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/localization/generated/app_localizations.dart";
import "../../../../core/preferences/app_preferences.dart";
import "../../../../core/router/route_paths.dart";
import "../../../../core/theme/app_colors.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../../../core/theme/app_theme.dart";

/// Shown once, right after the email confirmation link signs a new user in
/// (see [pendingEmailConfirmationProvider]) — so coming back from the mail
/// app clearly says "it worked" instead of silently opening the feed.
class AccountConfirmedScreen extends ConsumerWidget {
  const AccountConfirmedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Theme(
      data: AppTheme.dark,
      child: Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: <Widget>[
                const Spacer(),
                Container(
                  width: 112,
                  height: 112,
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.brandGradient),
                  child: const Icon(Icons.check_rounded, size: 64, color: Colors.white),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  l10n.authConfirmedTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppColors.darkOnBackground,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.authConfirmedBody,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.darkOnSurfaceMuted),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      unawaited(ref.read(pendingEmailConfirmationProvider.notifier).set(false));
                      context.goTo(RoutePaths.home);
                    },
                    child: Text(l10n.authConfirmedStart),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
