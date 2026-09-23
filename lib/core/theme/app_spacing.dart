/// 4pt spacing scale. Use these tokens instead of raw numbers so density
/// stays consistent across features (CLAUDE.md section 64 — design system).
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double pill = 999;
}

/// Animation durations, kept centralized so motion feels consistent and can
/// be scaled down globally for reduced-motion accessibility settings.
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration medium = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 360);
}
