import "package:flutter_test/flutter_test.dart";

import "package:adgag/features/create_ad/domain/local_video_draft.dart";

void main() {
  group("LocalVideoDraft.isWithinConstraints", () {
    test("a 5s clip is within constraints", () {
      const LocalVideoDraft draft = LocalVideoDraft(filePath: "x.mp4", duration: Duration(seconds: 5));
      expect(draft.isWithinConstraints, isTrue);
    });

    test("a 1s clip is too short", () {
      const LocalVideoDraft draft = LocalVideoDraft(filePath: "x.mp4", duration: Duration(seconds: 1));
      expect(draft.isWithinConstraints, isFalse);
    });

    test("a 25s clip is too long", () {
      const LocalVideoDraft draft = LocalVideoDraft(filePath: "x.mp4", duration: Duration(seconds: 25));
      expect(draft.isWithinConstraints, isFalse);
    });

    test("exactly 10s is within constraints (inclusive upper bound)", () {
      const LocalVideoDraft draft = LocalVideoDraft(filePath: "x.mp4", duration: Duration(seconds: 10));
      expect(draft.isWithinConstraints, isTrue);
    });
  });
}
