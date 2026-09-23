import "package:flutter_test/flutter_test.dart";

import "package:adgag/features/subjects/domain/ad_subject.dart";

void main() {
  group("AdSubject.fromRow", () {
    test("maps a subject row", () {
      final AdSubject subject = AdSubject.fromRow(<String, dynamic>{
        "id": "subj1",
        "canonical_key": "sock",
        "display_name": "SOCK",
        "ads_count": 84291,
      });

      expect(subject.id, "subj1");
      expect(subject.canonicalKey, "sock");
      expect(subject.displayName, "SOCK");
      expect(subject.adsCount, 84291);
    });
  });
}
