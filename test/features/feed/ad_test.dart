import "package:flutter_test/flutter_test.dart";

import "package:adgag/features/feed/domain/ad.dart";
import "package:adgag/features/feed/domain/ad_status.dart";

void main() {
  group("AdStatus.fromDb", () {
    test("maps every known db value", () {
      for (final AdStatus status in AdStatus.values) {
        expect(AdStatus.fromDb(status.name), status);
      }
    });

    test("throws on an unknown value", () {
      expect(() => AdStatus.fromDb("not_a_status"), throwsArgumentError);
    });
  });

  group("Ad.fromRow", () {
    test("maps a ready ad row with all fields", () {
      final Ad ad = Ad.fromRow(<String, dynamic>{
        "id": "ad1",
        "user_id": "u1",
        "subject_id": "s1",
        "caption": "Some people are harder.",
        "playback_id": "pb1",
        "thumbnail_url": "https://example.com/thumb.jpg",
        "duration_ms": 8000,
        "status": "ready",
        "inspired_by_ad_id": null,
        "daily_challenge_id": null,
        "view_count": 100,
        "sold_count": 42,
        "comment_count": 3,
        "share_count": 1,
        "ad_this_count": 5,
        "created_at": "2026-01-01T00:00:00Z",
        "published_at": "2026-01-01T00:05:00Z",
      });

      expect(ad.status, AdStatus.ready);
      expect(ad.soldCount, 42);
      expect(ad.publishedAt, isNotNull);
      expect(ad.durationMs, 8000);
    });

    test("handles a draft row with null video/publish fields", () {
      final Ad ad = Ad.fromRow(<String, dynamic>{
        "id": "ad2",
        "user_id": "u1",
        "subject_id": "s1",
        "caption": null,
        "playback_id": null,
        "thumbnail_url": null,
        "duration_ms": null,
        "status": "draft",
        "inspired_by_ad_id": null,
        "daily_challenge_id": null,
        "view_count": 0,
        "sold_count": 0,
        "comment_count": 0,
        "share_count": 0,
        "ad_this_count": 0,
        "created_at": "2026-01-01T00:00:00Z",
        "published_at": null,
      });

      expect(ad.status, AdStatus.draft);
      expect(ad.publishedAt, isNull);
      expect(ad.playbackId, isNull);
    });
  });
}
