import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:permission_handler/permission_handler.dart" show openAppSettings;

import "../../../../core/localization/generated/app_localizations.dart";
import "../../../../core/preferences/app_preferences.dart";
import "../../../../core/push/push_gate.dart";
import "../../../../core/push/push_service.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../../notifications/domain/notification_preferences.dart";
import "../../../notifications/presentation/providers/notifications_providers.dart";

/// Settings > Notifications: the phone's permission state (with a way to
/// turn it on) and one switch per kind of push. Switches save at once.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  PushPermission? _permission;

  /// Shown at once while saving; null = what the server has.
  NotificationPreferences? _pending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_readPermission());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the phone's settings: the permission may have changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_readPermission(registerIfGranted: true));
    }
  }

  Future<void> _readPermission({bool registerIfGranted = false}) async {
    final PushService push = ref.read(pushServiceProvider);
    final PushPermission p = await push.permission();
    if (registerIfGranted && p == PushPermission.granted && _permission != PushPermission.granted) {
      unawaited(push.register(ref.read(localeProvider)?.languageCode));
    }
    if (mounted) {
      setState(() => _permission = p);
    }
  }

  Future<void> _turnOn() async {
    final PushService push = ref.read(pushServiceProvider);
    if (_permission == PushPermission.denied) {
      await openAppSettings();
      return;
    }
    final PushPermission p = await push.requestPermission();
    if (mounted) {
      setState(() => _permission = p);
    }
  }

  Future<void> _save(NotificationPreferences next) async {
    setState(() => _pending = next);
    try {
      await ref.read(notificationsRepositoryProvider).savePreferences(next);
      ref.invalidate(notificationPreferencesProvider);
      await ref.read(notificationPreferencesProvider.future);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).notifSaveFailed)));
      }
    } finally {
      if (mounted) {
        setState(() => _pending = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<NotificationPreferences> prefsAsync = ref.watch(notificationPreferencesProvider);
    final NotificationPreferences? prefs = _pending ?? prefsAsync.valueOrNull;
    final bool canSwitch = prefs != null && _permission != PushPermission.unavailable;

    Widget toggle(
      String title,
      bool Function(NotificationPreferences) get,
      NotificationPreferences Function(NotificationPreferences, bool) set,
    ) {
      return SwitchListTile(
        title: Text(title),
        value: prefs == null ? true : get(prefs),
        onChanged: canSwitch ? (bool v) => unawaited(_save(set(prefs, v))) : null,
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsNotifications)),
      body: ListView(
        children: <Widget>[
          if (_permission == PushPermission.unavailable)
            _Banner(icon: Icons.notifications_off_outlined, title: l10n.notifUnavailable)
          else if (_permission == PushPermission.denied || _permission == PushPermission.notDetermined)
            _Banner(
              icon: Icons.notifications_off_outlined,
              title: l10n.notifPushOffTitle,
              body: _permission == PushPermission.denied ? l10n.notifPushOffBody : null,
              action: _permission == PushPermission.denied ? l10n.notifOpenSettings : l10n.notifTurnOn,
              onAction: () => unawaited(_turnOn()),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
            child: Text(l10n.notifPrefsHint, style: Theme.of(context).textTheme.bodySmall),
          ),
          if (prefsAsync.hasError && prefs == null)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(l10n.genericLoadFailed),
            ),
          toggle(l10n.notifPrefFollowers, (p) => p.newFollowers, (p, v) => p.copyWith(newFollowers: v)),
          toggle(l10n.notifPrefReviews, (p) => p.reviews, (p, v) => p.copyWith(reviews: v)),
          toggle(l10n.notifPrefMentions, (p) => p.mentions, (p, v) => p.copyWith(mentions: v)),
          toggle(l10n.notifPrefAdThis, (p) => p.adThis, (p, v) => p.copyWith(adThis: v)),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.title, this.body, this.action, this.onAction});

  final IconData icon;
  final String title;
  final String? body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.titleSmall),
                if (body != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(body!, style: theme.textTheme.bodySmall),
                ],
                if (action != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  FilledButton.tonal(onPressed: onAction, child: Text(action!)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
