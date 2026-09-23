import "ad_event_type.dart";

/// Records Ad-level engagement events (CLAUDE.md section 26). Calls are
/// fire-and-forget from the caller's perspective — the implementation
/// owns batching so feature code never has to think about network
/// efficiency itself ("Do not send excessive network requests for every
/// millisecond").
abstract interface class AnalyticsService {
  void track(String adId, AdEventType type, {int? watchMs});

  /// Sends any buffered events immediately — call on app background/
  /// dispose so a session's tail events aren't lost waiting for the next
  /// timed flush.
  Future<void> flush();
}
