import "dart:async" show StreamSubscription, unawaited;
import "dart:io" show Platform;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../../features/notifications/presentation/providers/notifications_providers.dart";
import "../localization/generated/app_localizations.dart";
import "../preferences/app_preferences.dart";
import "../router/route_paths.dart";
import "../supabase/supabase_providers.dart";
import "push_service.dart";

final Provider<PushService> pushServiceProvider = Provider<PushService>((ref) {
  final SharedPreferences prefs = ref.watch(sharedPreferencesProvider);
  return PushService(ref.watch(supabaseClientProvider), prefs);
});

/// Wraps the signed-in app (AppShell's body): starts push for this device
/// (permission prompt the first time, token registration), re-registers
/// when the app's language changes, opens what a tapped push is about, and
/// refreshes the Notifications list when one arrives while the app is open.
class PushGate extends ConsumerStatefulWidget {
  const PushGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PushGate> createState() => _PushGateState();
}

class _PushGateState extends ConsumerState<PushGate> {
  StreamSubscription<PushTarget>? _opened;
  StreamSubscription<PushTarget>? _foreground;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final PushService push = ref.read(pushServiceProvider);
      unawaited(push.start(ref.read(localeProvider)?.languageCode));
      _opened = push.openedMessages().listen(_open);
      _foreground = push.foregroundMessages().listen(_onForeground);
    });
  }

  @override
  void dispose() {
    unawaited(_opened?.cancel());
    unawaited(_foreground?.cancel());
    super.dispose();
  }

  void _open(PushTarget target) {
    if (!mounted) {
      return;
    }
    final String? id = target.notificationId;
    if (id != null) {
      unawaited(
        ref
            .read(notificationsRepositoryProvider)
            .markRead(id)
            .then((_) => ref.invalidate(recentNotificationsProvider))
            .catchError((Object _) {}),
      );
    }
    final String? adId = target.adId;
    final String? username = target.actorUsername;
    if (adId != null) {
      unawaited(context.pushTo(RoutePaths.adDetailOf(adId)));
    } else if (username != null) {
      unawaited(context.pushTo(RoutePaths.userProfileOf(username)));
    }
  }

  void _onForeground(PushTarget target) {
    if (!mounted) {
      return;
    }
    ref.invalidate(recentNotificationsProvider);
    // iOS already shows the banner (foreground presentation options).
    final String? title = target.title;
    if (Platform.isAndroid && title != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(title),
          action: SnackBarAction(label: AppLocalizations.of(context).notifView, onPressed: () => _open(target)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // The pushes are written in the app's language: follow a change.
    ref.listen<Locale?>(localeProvider, (Locale? previous, Locale? next) {
      if (previous?.languageCode != next?.languageCode) {
        unawaited(ref.read(pushServiceProvider).register(next?.languageCode));
      }
    });
    return widget.child;
  }
}
