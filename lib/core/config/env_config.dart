/// Compile-time environment configuration.
///
/// Values are injected via `--dart-define-from-file=env/<env>.json` (see
/// README.md "Environments"). Nothing here is a secret: the Supabase anon
/// key is designed to be public and is only safe because Row Level Security
/// enforces access control server-side (CLAUDE.md section 68). No
/// service-role key, video-provider secret, or signing key is ever read
/// from client config — those live only in Supabase Edge Function secrets.
enum AppEnvironment { development, staging, production }

abstract final class EnvConfig {
  static const String _envName = String.fromEnvironment(
    "APP_ENV",
    defaultValue: "development",
  );

  static AppEnvironment get environment => switch (_envName) {
        "production" => AppEnvironment.production,
        "staging" => AppEnvironment.staging,
        _ => AppEnvironment.development,
      };

  static const String supabaseUrl = String.fromEnvironment("SUPABASE_URL");
  static const String supabaseAnonKey = String.fromEnvironment("SUPABASE_ANON_KEY");

  /// Deep link / universal link host, e.g. "adgag.app" (section 33/54).
  static const String appLinkHost = String.fromEnvironment(
    "APP_LINK_HOST",
    defaultValue: "adgag.app",
  );

  /// Firebase (push notifications). On iOS the app is configured from these
  /// values; Android reads android/app/google-services.json instead (needed
  /// there so a push can be handled while the app isn't running). Client
  /// config, not secrets — Firebase's own docs ship them in the app. Empty =
  /// push notifications off in this build.
  static const String firebaseProjectId = String.fromEnvironment("FIREBASE_PROJECT_ID");
  static const String firebaseMessagingSenderId = String.fromEnvironment("FIREBASE_MESSAGING_SENDER_ID");
  static const String firebaseIosApiKey = String.fromEnvironment("FIREBASE_IOS_API_KEY");
  static const String firebaseIosAppId = String.fromEnvironment("FIREBASE_IOS_APP_ID");

  static bool get isProduction => environment == AppEnvironment.production;

  /// Fails fast with a readable message instead of a null-Supabase crash
  /// deep in a widget tree if someone forgets `--dart-define-from-file`.
  static void assertConfigured() {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        "Missing Supabase configuration. Run with "
        "--dart-define-from-file=env/dev.json (copy env/dev.example.json "
        "first and fill in your Supabase project URL/anon key). "
        "See README.md > Environments.",
      );
    }
  }
}
