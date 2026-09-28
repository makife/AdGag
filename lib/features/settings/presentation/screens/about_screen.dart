import "package:flutter/material.dart";

import "../../../../core/localization/generated/app_localizations.dart";
import "../../../../core/theme/app_spacing.dart";

/// Settings > About. Home of the open source licences page — kept here,
/// two taps deep, rather than anywhere prominent.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAbout)),
      body: ListView(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: <Widget>[
                Image.asset("assets/branding/AdGagIkon.png", width: 72, height: 72),
                const SizedBox(height: AppSpacing.md),
                Text(l10n.appName, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.xs),
                Text(l10n.appTagline, textAlign: TextAlign.center),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(l10n.aboutOpenSourceLibraries),
            subtitle: Text(l10n.aboutOpenSourceLibrariesSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: l10n.appName,
              applicationIcon: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Image.asset("assets/branding/AdGagIkon.png", width: 48, height: 48),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
