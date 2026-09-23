/// Mirrors the `ad_event_type` Postgres enum
/// (supabase/migrations/0015_analytics.sql). CLAUDE.md section 26 — "a
/// swipe past a video should NOT automatically equal a meaningful view."
enum AdEventType {
  impression,
  playStarted,
  twoSecondView,
  completed,
  rewatched,
  shared,
  sold,
  adThis;

  String get dbValue => switch (this) {
        AdEventType.impression => "impression",
        AdEventType.playStarted => "play_started",
        AdEventType.twoSecondView => "two_second_view",
        AdEventType.completed => "completed",
        AdEventType.rewatched => "rewatched",
        AdEventType.shared => "shared",
        AdEventType.sold => "sold",
        AdEventType.adThis => "ad_this",
      };
}
