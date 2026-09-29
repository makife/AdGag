/// Sign-up age check. The Terms and privacy policy say AdGag is for people
/// 13 and older; sign-up asks for a birth date (neutrally — no hint of the
/// cut-off) and refuses below it. Only the yes/no result is kept.
abstract final class AgeGate {
  static const int minimumAge = 13;

  /// Whole years between [birthDate] and [today] (calendar dates only).
  static int ageOn(DateTime birthDate, DateTime today) {
    int age = today.year - birthDate.year;
    final bool hadBirthdayThisYear =
        today.month > birthDate.month || (today.month == birthDate.month && today.day >= birthDate.day);
    if (!hadBirthdayThisYear) {
      age--;
    }
    return age;
  }

  static bool isOldEnough(DateTime birthDate, DateTime today) => ageOn(birthDate, today) >= minimumAge;
}
