import "package:flutter_test/flutter_test.dart";

import "package:adgag/features/profile/domain/public_profile.dart";

void main() {
  group("PublicProfile.fromRow", () {
    test("maps a full row", () {
      final PublicProfile profile = PublicProfile.fromRow(<String, dynamic>{
        "id": "u1",
        "username": "rockfan",
        "display_name": "Rock Fan",
        "bio": "Harder than most.",
        "avatar_url": null,
      });

      expect(profile.username, "rockfan");
      expect(profile.displayName, "Rock Fan");
      expect(profile.bio, "Harder than most.");
    });

    test("handles a row with only required fields", () {
      final PublicProfile profile = PublicProfile.fromRow(<String, dynamic>{
        "id": "u2",
        "username": "sockguy",
      });

      expect(profile.displayName, isNull);
      expect(profile.bio, isNull);
    });
  });
}
