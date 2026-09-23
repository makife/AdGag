import "package:flutter_test/flutter_test.dart";

import "package:adgag/core/utils/username_validator.dart";

void main() {
  group("UsernameValidator.normalize", () {
    test("lowercases and strips invalid characters", () {
      expect(UsernameValidator.normalize("Sock.Guy!99"), "sockguy99");
    });

    test("trims whitespace", () {
      expect(UsernameValidator.normalize("  rocklover  "), "rocklover");
    });
  });

  group("UsernameValidator.isValid", () {
    test("accepts a valid lowercase username", () {
      expect(UsernameValidator.isValid("sock_lover99"), isTrue);
    });

    test("rejects usernames shorter than 3 characters", () {
      expect(UsernameValidator.isValid("ab"), isFalse);
    });

    test("rejects usernames starting with a digit", () {
      expect(UsernameValidator.isValid("99sock"), isFalse);
    });

    test("rejects uppercase characters", () {
      expect(UsernameValidator.isValid("SockLover"), isFalse);
    });

    test("rejects usernames longer than 20 characters", () {
      expect(UsernameValidator.isValid("a${'b' * 20}"), isFalse);
    });
  });

  group("UsernameValidator.validationError", () {
    test("returns null for a valid username", () {
      expect(UsernameValidator.validationError("rock_fan"), isNull);
    });

    test("returns a message for an invalid username", () {
      expect(UsernameValidator.validationError("1bad"), isNotNull);
    });
  });
}
