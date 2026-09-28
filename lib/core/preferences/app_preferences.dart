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
