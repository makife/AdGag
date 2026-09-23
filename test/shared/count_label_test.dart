import "package:flutter_test/flutter_test.dart";

import "package:adgag/shared/widgets/count_label.dart";

void main() {
  group("CountLabel.format", () {
    test("shows small counts as-is", () {
      expect(CountLabel.format(0), "0");
      expect(CountLabel.format(999), "999");
    });

    test("abbreviates thousands as K", () {
      expect(CountLabel.format(12800), "12.8K");
      expect(CountLabel.format(1000), "1.0K");
    });

    test("abbreviates millions as M", () {
      expect(CountLabel.format(2500000), "2.5M");
    });
  });
}
