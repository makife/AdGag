import "package:logging/logging.dart";

/// Thin structured-logging wrapper (CLAUDE.md section 55). Kept independent
/// of any specific crash-reporting vendor so one can be plugged in later by
/// changing only [AppLogger.init] — feature code just calls
/// `AppLogger.for_("Feed").warning(...)` and never imports the vendor SDK.
///
/// Never log secrets, auth tokens, or raw PII (section 55/45).
abstract final class AppLogger {
  static bool _initialized = false;

  static void init({required bool verbose}) {
    if (_initialized) {
      return;
    }
    _initialized = true;
    Logger.root.level = verbose ? Level.ALL : Level.INFO;
    Logger.root.onRecord.listen((LogRecord record) {
      // MVP: console only. Swap/augment this listener with a crash-reporting
      // SDK sink (e.g. Sentry/Crashlytics) without touching call sites.
      // ignore: avoid_print
      print("[${record.level.name}] ${record.loggerName}: ${record.message}"
          "${record.error != null ? ' | error=${record.error}' : ''}");
    });
  }

  static Logger named(String name) => Logger(name);
}
