import "package:adgag/core/utils/age_gate.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  final DateTime today = DateTime(2026, 9, 29);

  test("13th birthday today is old enough", () {
    expect(AgeGate.isOldEnough(DateTime(2013, 9, 29), today), isTrue);
  });

  test("one day before the 13th birthday is not", () {
    expect(AgeGate.isOldEnough(DateTime(2013, 9, 30), today), isFalse);
    expect(AgeGate.ageOn(DateTime(2013, 9, 30), today), 12);
  });

  test("birthday later in the year counts the previous age", () {
    expect(AgeGate.ageOn(DateTime(2000, 12, 1), today), 25);
    expect(AgeGate.ageOn(DateTime(2000, 1, 1), today), 26);
  });

  test("29 February birthday on a non-leap year counts from 1 March", () {
    expect(AgeGate.ageOn(DateTime(2012, 2, 29), DateTime(2025, 2, 28)), 12);
    expect(AgeGate.ageOn(DateTime(2012, 2, 29), DateTime(2025, 3, 1)), 13);
  });
}
