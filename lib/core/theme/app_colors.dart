import "package:flutter/material.dart";

/// Brand palette derived from the AdGag mark: a near-black canvas with a
/// single turquoise family — deep ocean blue -> turquoise -> mint — used
/// sparingly as an accent (the "AD" action, active states, the brand mark
/// itself), never as a full-screen wash. Chosen 2026-09-28 to move away from
/// the Instagram-like blue/purple/pink/orange (and away from TikTok's
/// turquoise + pink). Video stays the dominant visual element (CLAUDE.md
/// section 35/64). Mirrored by hand in the native editors: AdGagTheme.kt
/// (Android) and EditorPalette (iOS) — keep all three in sync.
abstract final class AppColors {
  // Brand gradient stops (left -> right in the logo mark).
  static const Color brandDeep = Color(0xFF2B6CE6);
  static const Color brandOcean = Color(0xFF1FA3C9);
  static const Color brandTurquoise = Color(0xFF16C5C0);
  static const Color brandMint = Color(0xFF3EE6A8);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: <Color>[brandDeep, brandOcean, brandTurquoise, brandMint],
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

  // SOLD is the primary positive reaction — the brand turquoise, so it reads
  // as a distinct, ownable color across themes.
  static const Color sold = brandTurquoise;
}
