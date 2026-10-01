import "package:adgag/features/notifications/domain/notification_preferences.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  group("NotificationPreferences", () {
    test("no saved row means every push is on", () {
      final NotificationPreferences p = NotificationPreferences.fromRow(null);
      expect(<bool>[p.newFollowers, p.reviews, p.mentions, p.adThis], everyElement(isTrue));
    });

    test("reads the saved switches", () {
      final NotificationPreferences p = NotificationPreferences.fromRow(<String, dynamic>{
        "new_followers": false,
        "reviews": true,
        "mentions": false,
        "ad_this": true,
      });
      expect(p.newFollowers, isFalse);
      expect(p.reviews, isTrue);
      expect(p.mentions, isFalse);
      expect(p.adThis, isTrue);
    });

    test("toRow writes the DB column names for the given user", () {
      final Map<String, dynamic> row =
          const NotificationPreferences().copyWith(mentions: false).toRow("user-1");
      expect(row["user_id"], "user-1");
      expect(row["new_followers"], isTrue);
      expect(row["reviews"], isTrue);
      expect(row["mentions"], isFalse);
      expect(row["ad_this"], isTrue);
    });
  });
}
