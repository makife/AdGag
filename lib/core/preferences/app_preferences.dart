import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:shared_preferences/shared_preferences.dart";

/// Loaded once in `main()` and injected via a ProviderScope override, so
/// every preference below can be read synchronously on the first frame
/// (no flash of the wrong theme/language).
final Provider<SharedPreferences> sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError("sharedPreferencesProvider must be overridden in main()"),
);

/// Settings > Appearance. Per device, not per account — like Instagram.
final class ThemeModeController extends Notifier<ThemeMode> {
  static const String _key = "theme_mode";

  @override
  ThemeMode build() {
    final String? stored = ref.watch(sharedPreferencesProvider).getString(_key);
    return ThemeMode.values.firstWhere((ThemeMode m) => m.name == stored, orElse: () => ThemeMode.system);
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(sharedPreferencesProvider).setString(_key, mode.name);
  }
}

final NotifierProvider<ThemeModeController, ThemeMode> themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

/// Settings > Language. `null` = follow the device language.
final class LocaleController extends Notifier<Locale?> {
  static const String _key = "locale";

  @override
  Locale? build() {
    final String? stored = ref.watch(sharedPreferencesProvider).getString(_key);
    return stored == null ? null : Locale(stored);
  }

  Future<void> set(Locale? locale) async {
    state = locale;
    final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
    if (locale == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, locale.languageCode);
    }
  }
}

final NotifierProvider<LocaleController, Locale?> localeProvider =
    NotifierProvider<LocaleController, Locale?>(LocaleController.new);

/// Set when sign-up ends with "check your email". The confirmation link
/// signs the user in by itself, which used to drop them straight onto the
/// feed with no sign the link worked; while this is set, the router shows
/// the "Your account is confirmed" page once after that sign-in.
final class PendingEmailConfirmationController extends Notifier<bool> {
  static const String _key = "pending_email_confirmation";

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? false;

  Future<void> set(bool pending) async {
    state = pending;
    final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
    if (pending) {
      await prefs.setBool(_key, true);
    } else {
      await prefs.remove(_key);
    }
  }
}

final NotifierProvider<PendingEmailConfirmationController, bool> pendingEmailConfirmationProvider =
    NotifierProvider<PendingEmailConfirmationController, bool>(PendingEmailConfirmationController.new);

/// Set on this device once the sign-up age screen gets a birth date under
/// AgeGate.minimumAge (13). Sign-up then stays closed here, so going back and
/// picking another date doesn't get around it (the usual "neutral age
/// screen" practice). The birth date itself is never stored or sent.
final class AgeGateBlockedController extends Notifier<bool> {
  static const String _key = "age_gate_blocked";

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? false;

  Future<void> block() async {
    state = true;
    await ref.read(sharedPreferencesProvider).setBool(_key, true);
  }
}

final NotifierProvider<AgeGateBlockedController, bool> ageGateBlockedProvider =
    NotifierProvider<AgeGateBlockedController, bool>(AgeGateBlockedController.new);
