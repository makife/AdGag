import "package:flutter/material.dart";

/// Brand palette derived from the AdGag mark: a near-black canvas with a
/// signature purple -> blue -> pink -> orange gradient used sparingly as an
/// accent (the "AD" action, active states, the brand mark itself) — never as
/// a full-screen wash. Video stays the dominant visual element (CLAUDE.md
/// section 35/64).
abstract final class AppColors {
  // Brand gradient stops (left -> right in the logo mark).
  static const Color gradientBlue = Color(0xFF2E5BFF);
  static const Color gradientPurple = Color(0xFF9B2FFF);
  static const Color gradientPink = Color(0xFFFF2FB0);
  static const Color gradientOrange = Color(0xFFFF8A2F);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: <Color>[gradientBlue, gradientPurple, gradientPink, gradientOrange],
  );

  // Dark theme (primary video-feed presentation — section 35).
  static const Color darkBackground = Color(0xFF000000);
  static const Color darkSurface = Color(0xFF121214);
  static const Color darkSurfaceElevated = Color(0xFF1C1C1F);
  static const Color darkOnBackground = Color(0xFFF5F5F7);
  static const Color darkOnSurfaceMuted = Color(0xFFA0A0A8);
  static const Color darkBorder = Color(0x1FFFFFFF);
  static const Color darkOverlayScrim = Color(0x99000000);

  // Light theme.
  static const Color lightBackground = Color(0xFFFAFAFA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFF0F0F2);
  static const Color lightOnBackground = Color(0xFF121214);
  static const Color lightOnSurfaceMuted = Color(0xFF5C5C66);
  static const Color lightBorder = Color(0x1F000000);

  // Semantic / functional.
  static const Color success = Color(0xFF2FD97F);
  static const Color danger = Color(0xFFFF4D4D);
  static const Color warning = Color(0xFFFFB020);

  // SOLD is the primary positive reaction — pinned to the pink stop of the
  // brand gradient so it reads as a distinct, ownable color across themes.
  static const Color sold = gradientPink;
}
