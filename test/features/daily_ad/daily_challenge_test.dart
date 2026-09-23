import "package:flutter_test/flutter_test.dart";

import "package:adgag/features/daily_ad/domain/daily_challenge.dart";

void main() {
  group("DailyChallenge.fromRow", () {
    test("maps a full row", () {
      final DailyChallenge challenge = DailyChallenge.fromRow(<String, dynamic>{
        "id": "c1",
        "subject_id": "s1",
        "title": "Today's Ad",
        "prompt": "Sell it in 10 seconds.",
        "icon_url": null,
        "starts_at": "2026-01-01T00:00:00Z",
        "ends_at": "2026-01-02T00:00:00Z",
        "participant_count": 42,
      });

      expect(challenge.title, "Today's Ad");
      expect(challenge.participantCount, 42);
      expect(challenge.endsAt.isAfter(challenge.startsAt), isTrue);
    });
  });
}
