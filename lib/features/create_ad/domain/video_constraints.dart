/// Mirrors the `duration_range` CHECK on `ads` (supabase/migrations/
/// 0019_thirty_second_ads.sql). The product owner raised the cap from
/// CLAUDE.md section 4's original 10s to 30s (2026-09-26): one take of up
/// to 30s, or several shorter takes stitched together in the native
/// editor. The native editor mirrors this as `MaxTotalDurationMs`.
/// Client-side enforcement here is what actually stops most out-of-range
/// uploads before they ever reach the server; the DB CHECK is the
/// backstop, not the primary UX.
abstract final class VideoConstraints {
  static const Duration min = Duration(milliseconds: 1500);
  static const Duration max = Duration(milliseconds: 30000);
}
