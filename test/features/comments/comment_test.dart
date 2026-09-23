import "package:flutter_test/flutter_test.dart";

import "package:adgag/features/comments/domain/comment.dart";

void main() {
  group("Comment.fromRow", () {
    test("maps a row with an embedded username", () {
      final Comment comment = Comment.fromRow(<String, dynamic>{
        "id": "c1",
        "ad_id": "ad1",
        "user_id": "u1",
        "body": "Some people are harder.",
        "created_at": "2026-01-01T00:00:00Z",
        "profiles": <String, dynamic>{"username": "rockfan"},
      });

      expect(comment.body, "Some people are harder.");
      expect(comment.username, "rockfan");
    });

    test("leaves username null without the embed", () {
      final Comment comment = Comment.fromRow(<String, dynamic>{
        "id": "c2",
        "ad_id": "ad1",
        "user_id": "u1",
        "body": "Nice.",
        "created_at": "2026-01-01T00:00:00Z",
      });

      expect(comment.username, isNull);
    });
  });
}
