import "package:flutter/material.dart";

/// Editorial-leaning type scale (section 35: "tasteful typography inspired
/// by advertising/editorial design"). Uses the Flutter default font family
/// for MVP so no custom font licensing/asset work blocks Phase A; swap
/// [AppTypography.fontFamily] once a brand typeface is chosen.
abstract final class AppTypography {
  static const String? fontFamily = null; // null = platform default

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
  static const FontWeight black = FontWeight.w900;

  static TextTheme textTheme(Color onBackground) {
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 40,
        fontWeight: black,
        letterSpacing: -0.5,
        color: onBackground,
      ),
      headlineLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 28,
        fontWeight: bold,
        letterSpacing: -0.25,
        color: onBackground,
      ),
      headlineSmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 22,
        fontWeight: bold,
        color: onBackground,
      ),
      titleLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 18,
        fontWeight: semibold,
        color: onBackground,
      ),
      titleMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 16,
        fontWeight: semibold,
        color: onBackground,
      ),
      bodyLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 16,
        fontWeight: regular,
        color: onBackground,
      ),
      bodyMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: regular,
        color: onBackground,
      ),
      labelLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: semibold,
        letterSpacing: 0.2,
        color: onBackground,
      ),
      labelMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 12,
        fontWeight: semibold,
        letterSpacing: 0.4,
        color: onBackground,
      ),
      labelSmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 11,
        fontWeight: medium,
        letterSpacing: 0.4,
        color: onBackground,
      ),
    );
  }
}
