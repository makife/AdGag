import "package:flutter_test/flutter_test.dart";

import "package:adgag/core/analytics/ad_event_type.dart";

void main() {
  group("AdEventType.dbValue", () {
    // Mirrors the ad_event_type Postgres enum exactly
    // (0015_analytics.sql) — a mismatch here silently breaks every
    // analytics insert with a Postgres enum cast error.
    const Map<AdEventType, String> expected = <AdEventType, String>{
      AdEventType.impression: "impression",
      AdEventType.playStarted: "play_started",
      AdEventType.twoSecondView: "two_second_view",
      AdEventType.completed: "completed",
      AdEventType.rewatched: "rewatched",
      AdEventType.shared: "shared",
      AdEventType.sold: "sold",
      AdEventType.adThis: "ad_this",
    };

    for (final entry in expected.entries) {
      test("${entry.key} maps to '${entry.value}'", () {
        expect(entry.key.dbValue, entry.value);
      });
    }

    test("every AdEventType value is covered", () {
      expect(expected.keys.toSet(), AdEventType.values.toSet());
    });
  });
}
