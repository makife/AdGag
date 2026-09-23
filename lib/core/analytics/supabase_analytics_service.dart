import "dart:async";

import "package:supabase_flutter/supabase_flutter.dart" as supa;

import "../utils/app_logger.dart";
import "ad_event_type.dart";
import "analytics_service.dart";

/// Buffers events and flushes in batches — either every [flushInterval] or
/// once [maxBufferSize] is reached, whichever comes first (CLAUDE.md
/// section 26). A failed flush drops that batch rather than retrying
/// indefinitely: analytics data is valuable in aggregate, not worth
/// complex retry logic that could pile up unbounded memory if the network
/// is down for a while.
final class SupabaseAnalyticsService implements AnalyticsService {
  SupabaseAnalyticsService(
    this._client, {
    this.flushInterval = const Duration(seconds: 10),
    this.maxBufferSize = 20,
  }) {
    _timer = Timer.periodic(flushInterval, (_) => unawaited(flush()));
  }

  final supa.SupabaseClient _client;
  final Duration flushInterval;
  final int maxBufferSize;
  final _log = AppLogger.named("Analytics");

  final List<Map<String, dynamic>> _buffer = <Map<String, dynamic>>[];
  Timer? _timer;

  @override
  void track(String adId, AdEventType type, {int? watchMs}) {
    final String? userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return; // Analytics rows are attributed; skip if signed out.
    }
    _buffer.add(<String, dynamic>{
      "ad_id": adId,
      "user_id": userId,
      "event_type": type.dbValue,
      "watch_ms": watchMs,
    });
    if (_buffer.length >= maxBufferSize) {
      unawaited(flush());
    }
  }

  @override
  Future<void> flush() async {
    if (_buffer.isEmpty) {
      return;
    }
    final List<Map<String, dynamic>> batch = List<Map<String, dynamic>>.of(_buffer);
    _buffer.clear();
    try {
      await _client.from("ad_events").insert(batch);
    } catch (e) {
      _log.warning("Failed to flush ${batch.length} analytics event(s)", e);
    }
  }

  void dispose() {
    _timer?.cancel();
  }
}
