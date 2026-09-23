import "package:flutter_test/flutter_test.dart";

import "package:adgag/features/auth/domain/app_user.dart";

void main() {
  group("AppUser.fromProfileRow", () {
    test("maps a full profiles row", () {
      final AppUser user = AppUser.fromProfileRow(
        <String, dynamic>{"id": "u1", "username": "rockfan", "display_name": "Rock Fan"},
        email: "rockfan@example.com",
      );

      expect(user.id, "u1");
      expect(user.username, "rockfan");
      expect(user.displayName, "Rock Fan");
      expect(user.email, "rockfan@example.com");
    });

    test("falls back to username when display_name is null", () {
      final AppUser user = AppUser.fromProfileRow(
        <String, dynamic>{"id": "u2", "username": "sockguy", "display_name": null},
        email: "sockguy@example.com",
      );

      expect(user.displayName, "sockguy");
    });
  });
}
