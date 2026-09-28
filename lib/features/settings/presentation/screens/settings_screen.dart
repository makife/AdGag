import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/localization/generated/app_localizations.dart";
import "../../../../core/preferences/app_preferences.dart";
import "../../../../core/router/route_paths.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../../auth/presentation/providers/auth_providers.dart";
import "../widgets/settings_tiles.dart";

/// Settings, laid out like Instagram's: grouped rows under quiet section
/// headings, and "Log out" as plain red text at the very bottom instead of
/// a button on the profile. Only things that actually work are listed —
/// no placeholder rows for features that don't exist yet (notification
/// preferences, account deletion, policy pages need a backend/hosting
/// first).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const Map<String, String> _languageNames = <String, String>{"en": "English", "tr": "Türkçe"};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeMode themeMode = ref.watch(themeModeProvider);
    final Locale? locale = ref.watch(localeProvider);
    final String? username = ref.watch(currentAppUserProvider).valueOrNull?.username;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: <Widget>[
          SettingsSectionHeader(l10n.settingsSectionAccount),
          SettingsTile(
            icon: Icons.person_outline,
            title: l10n.settingsEditProfile,
            onTap: () => unawaited(context.pushTo(RoutePaths.editProfile)),
          ),
          SettingsTile(
            icon: Icons.manage_accounts_outlined,
            title: l10n.settingsAccount,
            subtitle: l10n.settingsAccountSubtitle,
            onTap: () => unawaited(context.pushTo(RoutePaths.settingsAccount)),
          ),
          SettingsSectionHeader(l10n.settingsSectionPrivacy),
          SettingsTile(
            icon: Icons.block,
            title: l10n.settingsBlocked,
            onTap: () => unawaited(context.pushTo(RoutePaths.settingsBlocked)),
          ),
          SettingsSectionHeader(l10n.settingsSectionApp),
          SettingsTile(
            icon: Icons.language,
            title: l10n.settingsLanguage,
            value: locale == null ? l10n.settingsLanguageSystem : _languageNames[locale.languageCode],
            onTap: () => unawaited(_pickLanguage(context, ref, locale)),
          ),
          SettingsTile(
            icon: Icons.dark_mode_outlined,
            title: l10n.settingsAppearance,
            value: _themeLabel(l10n, themeMode),
            onTap: () => unawaited(_pickTheme(context, ref, themeMode)),
          ),
          SettingsSectionHeader(l10n.settingsSectionMore),
          SettingsTile(
            icon: Icons.info_outline,
            title: l10n.settingsAbout,
            onTap: () => unawaited(context.pushTo(RoutePaths.settingsAbout)),
          ),
          SettingsSectionHeader(l10n.settingsSectionLogin),
          ListTile(
            title: Text(
              l10n.settingsLogOut(username == null ? "" : "@$username"),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () => unawaited(_confirmLogOut(context, ref)),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  static String _themeLabel(AppLocalizations l10n, ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => l10n.settingsThemeSystem,
      ThemeMode.light => l10n.settingsThemeLight,
      ThemeMode.dark => l10n.settingsThemeDark,
    };
  }

  Future<void> _pickLanguage(BuildContext context, WidgetRef ref, Locale? current) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<(String?, String)> options = <(String?, String)>[
      (null, l10n.settingsLanguageSystem),
      for (final MapEntry<String, String> e in _languageNames.entries) (e.key, e.value),
    ];
    final String? currentCode = current?.languageCode;
    final (String?,)? picked = await showModalBottomSheet<(String?,)>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: RadioGroup<String?>(
          groupValue: currentCode,
          onChanged: (String? code) => Navigator.of(sheetContext).pop((code,)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final (String? code, String label) in options)
                RadioListTile<String?>(value: code, title: Text(label)),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      await ref.read(localeProvider.notifier).set(picked.$1 == null ? null : Locale(picked.$1!));
    }
  }

  Future<void> _pickTheme(BuildContext context, WidgetRef ref, ThemeMode current) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeMode? picked = await showModalBottomSheet<ThemeMode>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: RadioGroup<ThemeMode>(
          groupValue: current,
          onChanged: (ThemeMode? mode) => Navigator.of(sheetContext).pop(mode),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final ThemeMode mode in ThemeMode.values)
                RadioListTile<ThemeMode>(value: mode, title: Text(_themeLabel(l10n, mode))),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      await ref.read(themeModeProvider.notifier).set(picked);
    }
  }

  Future<void> _confirmLogOut(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.settingsLogOutConfirmTitle),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.genericCancel)),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              l10n.settingsLogOutConfirm,
              style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      // The router's auth redirect takes the user to onboarding.
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }
}
