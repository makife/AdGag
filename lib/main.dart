import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "app.dart";
import "core/config/env_config.dart";
import "core/utils/app_logger.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AppLogger.init(verbose: !EnvConfig.isProduction);
  EnvConfig.assertConfigured();

  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    anonKey: EnvConfig.supabaseAnonKey,
    // Deep links (section 33/54) land through go_router; Supabase only
    // needs its own auth-callback scheme for OAuth/email-link redirects.
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  runApp(const ProviderScope(child: AdGagApp()));
}
