import "daily_challenge.dart";

/// CLAUDE.md section 11: "Daily challenge time boundaries should be
/// server-controlled, not device-controlled." [getCurrent] always defers
/// to the server's `get_current_daily_challenge()` — the client never
/// computes "is today's challenge active" from the device clock.
abstract interface class DailyAdRepository {
  Future<DailyChallenge?> getCurrent();
}
