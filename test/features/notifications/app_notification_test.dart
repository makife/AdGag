import "package:flutter_test/flutter_test.dart";

import "package:adgag/features/notifications/domain/app_notification.dart";

void main() {
  group("NotificationType.fromDb", () {
    test("maps every known db value", () {
      expect(NotificationType.fromDb("new_follower"), NotificationType.newFollower);
      expect(NotificationType.fromDb("new_review"), NotificationType.newReview);
      expect(NotificationType.fromDb("ad_this"), NotificationType.adThis);
      expect(NotificationType.fromDb("review_reply"), NotificationType.reviewReply);
      expect(NotificationType.fromDb("mention"), NotificationType.mention);
    });

    test("returns null for a type this build doesn't know", () {
      expect(NotificationType.fromDb("not_a_type"), isNull);
    });
  });

  group("AppNotification.tryFromRow", () {
    test("skips a row of an unknown type instead of throwing", () {
      expect(
        AppNotification.tryFromRow(<String, dynamic>{
          "id": "n0",
          "type": "some_future_type",
          "created_at": "2026-01-01T00:00:00Z",
          "payload": <String, dynamic>{},
        }),
        isNull,
      );
    });

    test("maps a review notification with an embedded actor and ad_id payload", () {
      final AppNotification notification = AppNotification.tryFromRow(<String, dynamic>{
        "id": "n1",
        "type": "new_review",
        "created_at": "2026-01-01T00:00:00Z",
        "payload": <String, dynamic>{"ad_id": "ad1", "comment_id": "c1"},
        "actor_id": "u2",
        "profiles": <String, dynamic>{"username": "rockfan"},
        "read_at": null,
      })!;

      expect(notification.type, NotificationType.newReview);
      expect(notification.actorUsername, "rockfan");
      expect(notification.adId, "ad1");
      expect(notification.isUnread, isTrue);
    });

    test("marks isUnread false once read_at is set", () {
      final AppNotification notification = AppNotification.tryFromRow(<String, dynamic>{
        "id": "n2",
        "type": "new_follower",
        "created_at": "2026-01-01T00:00:00Z",
        "payload": <String, dynamic>{},
        "actor_id": "u3",
        "read_at": "2026-01-01T01:00:00Z",
      })!;

      expect(notification.isUnread, isFalse);
      expect(notification.adId, isNull);
    });
  });
}
