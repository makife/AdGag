import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "app.dart";
import "core/licenses/native_licenses.dart";
import "core/preferences/app_preferences.dart";
import "core/config/env_config.dart";
import "core/utils/app_logger.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only, like every short-video app: turning the phone never
  // rotates the UI. The camera still records a sideways phone as landscape
  // (camera_record_view.dart reads the physical orientation).
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[DeviceOrientation.portraitUp]);

  AppLogger.init(verbose: !EnvConfig.isProduction);
  EnvConfig.assertConfigured();

  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    // supabase_flutter 2.17 deprecated `anonKey` in favor of
    // `publishableKey` (Supabase's newer API-key terminology) — same
    // value, non-deprecated parameter name.
    publishableKey: EnvConfig.supabaseAnonKey,
    // Deep links (section 33/54) land through go_router; Supabase only
    // needs its own auth-callback scheme for OAuth/email-link redirects.
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  registerNativeLicenses();
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const AdGagApp(),
    ),
  );
}
