/// Mirrors the `duration_range` CHECK on `ads`
/// (supabase/migrations/0005_ads.sql) and CLAUDE.md section 4: "maximum
/// duration is 10 seconds... minimum should be configurable, initially
/// around 2 seconds." Client-side enforcement here is what actually stops
/// most out-of-range uploads before they ever reach the server; the DB
/// CHECK is the backstop, not the primary UX.
abstract final class VideoConstraints {
  static const Duration min = Duration(milliseconds: 1500);
  static const Duration max = Duration(milliseconds: 10000);
}
