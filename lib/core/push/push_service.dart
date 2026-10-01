import "dart:async" show StreamSubscription, unawaited;
import "dart:io" show Platform;
import "dart:ui" show PlatformDispatcher;

import "package:firebase_core/firebase_core.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "package:uuid/uuid.dart";

import "../config/env_config.dart";
import "../localization/generated/app_localizations.dart";
import "../utils/app_logger.dart";

/// Where the app is with push permission.
enum PushPermission {
  /// Firebase isn't configured in this build (or failed to start).
  unavailable,

  /// Never asked yet.
  notDetermined,
  denied,
  granted,
}

/// What a tapped (or foreground) push is about — from its `data`.
final class PushTarget {
  const PushTarget({required this.notificationId, this.adId, this.actorUsername, this.title});

  final String? notificationId;
  final String? adId;
  final String? actorUsername;

  /// The visible text (foreground messages only).
  final String? title;

  static PushTarget fromMessage(RemoteMessage m) => PushTarget(
        notificationId: m.data["notification_id"] as String?,
        adId: m.data["ad_id"] as String?,
        actorUsername: m.data["actor_username"] as String?,
        title: m.notification?.title,
      );
}

/// Push notifications through Firebase Cloud Messaging on both platforms
/// (APNs is configured inside the Firebase project). The server side is the
/// send-push Edge Function, fed by a trigger on `notifications`
/// (0024_push_notifications.sql); this class only keeps THIS device's token
/// registered for the signed-in user, in the app's current language, and
/// reports taps.
///
/// Every call is safe without Firebase (a build without the config): it
/// reports [PushPermission.unavailable] and does nothing.
final class PushService {
  PushService(this._client, this._prefs);

  final SupabaseClient _client;
  final SharedPreferences _prefs;
  final _log = AppLogger.named("PushService");

  static const String _askedKey = "push_permission_asked";
  static const String _installationKey = "push_installation_id";

  /// A random id for this install of the app, sent with the token: the
  /// server keeps one token per installation, so a refreshed token (or a
  /// language change / account switch) replaces the old row instead of
  /// piling up — one phone got the same push several times.
  String get _installationId {
    final String? existing = _prefs.getString(_installationKey);
    if (existing != null) {
      return existing;
    }
    final String id = const Uuid().v4();
    unawaited(_prefs.setString(_installationKey, id));
    return id;
  }

  Future<bool>? _firebase;
  String? _token;
  String? _languageCode;
  StreamSubscription<String>? _refreshSub;

  Future<bool> _ensureFirebase() => _firebase ??= _initFirebase();

  Future<bool> _initFirebase() async {
    try {
      if (Firebase.apps.isEmpty) {
        if (Platform.isIOS) {
          if (EnvConfig.firebaseIosApiKey.isEmpty || EnvConfig.firebaseIosAppId.isEmpty) {
            return false;
          }
          await Firebase.initializeApp(
            options: const FirebaseOptions(
              apiKey: EnvConfig.firebaseIosApiKey,
              appId: EnvConfig.firebaseIosAppId,
              messagingSenderId: EnvConfig.firebaseMessagingSenderId,
              projectId: EnvConfig.firebaseProjectId,
              iosBundleId: "com.ergan.adgag",
            ),
          );
        } else {
          // Android: from google-services.json (absent = no push in this build).
          await Firebase.initializeApp();
        }
      }
      // iOS shows a push that arrives while the app is open as a banner too.
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      return true;
    } catch (e, st) {
      _log.warning("Firebase unavailable — push notifications off", e, st);
      return false;
    }
  }

  Future<PushPermission> permission() async {
    if (!await _ensureFirebase()) {
      return PushPermission.unavailable;
    }
    final NotificationSettings s = await FirebaseMessaging.instance.getNotificationSettings();
    return switch (s.authorizationStatus) {
      AuthorizationStatus.authorized || AuthorizationStatus.provisional => PushPermission.granted,
      AuthorizationStatus.denied || AuthorizationStatus.deniedPermanently => PushPermission.denied,
      AuthorizationStatus.notDetermined => PushPermission.notDetermined,
    };
  }

  /// Shows the system prompt (iOS; Android 13+), then registers this device.
  Future<PushPermission> requestPermission() async {
    if (!await _ensureFirebase()) {
      return PushPermission.unavailable;
    }
    await _prefs.setBool(_askedKey, true);
    await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
    final PushPermission result = await permission();
    if (result == PushPermission.granted) {
      await register(_languageCode);
    }
    return result;
  }

  /// Called once the signed-in app is showing: asks for permission the
  /// first time ever, then keeps the token registered.
  Future<void> start(String? languageCode) async {
    _languageCode = languageCode;
    if (!await _ensureFirebase()) {
      return;
    }
    final PushPermission p = await permission();
    if (p == PushPermission.notDetermined && !(_prefs.getBool(_askedKey) ?? false)) {
      await requestPermission();
      return;
    }
    if (p == PushPermission.granted) {
      await register(languageCode);
    }
  }

  /// Saves this device's token for the signed-in user with the language the
  /// app shows ([languageCode], null = the phone's language). Re-call when
  /// the app's language changes.
  Future<void> register(String? languageCode) async {
    _languageCode = languageCode;
    if (_client.auth.currentUser == null || !await _ensureFirebase()) {
      return;
    }
    try {
      final FirebaseMessaging fm = FirebaseMessaging.instance;
      if (Platform.isIOS) {
        // FCM can't make a token before APNs has given the app one.
        for (int i = 0; i < 10 && await fm.getAPNSToken() == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
      final String? token = await fm.getToken();
      if (token == null) {
        return;
      }
      _token = token;
      await _save(token);
      _refreshSub ??= fm.onTokenRefresh.listen((String t) {
        _token = t;
        unawaited(_save(t).catchError((Object e) => _log.warning("token refresh save failed", e)));
      });
    } catch (e, st) {
      _log.warning("Push registration failed", e, st);
    }
  }

  Future<void> _save(String token) async {
    if (_client.auth.currentUser == null) {
      return;
    }
    await _client.rpc<void>("register_device_token", params: <String, Object?>{
      "p_token": token,
      "p_platform": Platform.isIOS ? "ios" : "android",
      "p_locale": _effectiveLanguage(_languageCode),
      "p_installation_id": _installationId,
    },);
  }

  /// Before signing out: this device stops receiving the account's pushes.
  Future<void> unregister() async {
    final String? token = _token;
    await _refreshSub?.cancel();
    _refreshSub = null;
    _token = null;
    if (token == null) {
      return;
    }
    try {
      await _client.rpc<void>("unregister_device_token", params: <String, Object?>{"p_token": token});
    } catch (e) {
      _log.warning("unregister_device_token failed", e);
    }
  }

  /// Pushes that arrive while the app is open.
  Stream<PushTarget> foregroundMessages() async* {
    if (!await _ensureFirebase()) {
      return;
    }
    yield* FirebaseMessaging.onMessage.map(PushTarget.fromMessage);
  }

  /// Taps on a push: the one that launched the app (if any), then later ones.
  Stream<PushTarget> openedMessages() async* {
    if (!await _ensureFirebase()) {
      return;
    }
    final RemoteMessage? initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      yield PushTarget.fromMessage(initial);
    }
    yield* FirebaseMessaging.onMessageOpenedApp.map(PushTarget.fromMessage);
  }

  /// A language the server has texts for; otherwise English.
  static String _effectiveLanguage(String? code) {
    final String c = code ?? PlatformDispatcher.instance.locale.languageCode;
    final bool supported = AppLocalizations.supportedLocales.any((l) => l.languageCode == c);
    return supported ? c : "en";
  }
}
