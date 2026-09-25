package com.adgag.adgag.editor

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * The native editor's own color/type tokens, hand-mirrored from the
 * Flutter app's design system (`lib/core/theme/app_colors.dart` /
 * `app_typography.dart` / `app_spacing.dart`) — Compose is a separate UI
 * toolkit with no way to share those Dart constants directly, so this is
 * a deliberate, value-for-value port, not a fresh design. Keep these in
 * sync if the Flutter tokens ever change.
 */
object AdGagColors {
    val Background = Color(0xFF000000)
    val Surface = Color(0xFF121214)
    val SurfaceElevated = Color(0xFF1C1C1F)
    val OnBackground = Color(0xFFF5F5F7)
    val OnSurfaceMuted = Color(0xFFA0A0A8)
    val Border = Color(0x1FFFFFFF)
    val OverlayScrim = Color(0x99000000)

    val GradientBlue = Color(0xFF2E5BFF)
    val GradientPurple = Color(0xFF9B2FFF)
    val GradientPink = Color(0xFFFF2FB0)
    val GradientOrange = Color(0xFFFF8A2F)

    val Danger = Color(0xFFFF4D4D)
    val Success = Color(0xFF2FD97F)

    /** The "AD" tab / brand-mark gradient — used sparingly as an accent, never a full wash. */
    val BrandGradient = Brush.horizontalGradient(
        listOf(GradientBlue, GradientPurple, GradientPink, GradientOrange),
    )
}

/** 4dp spacing scale — direct port of `AppSpacing` (app_spacing.dart). */
object AdGagSpacing {
    val xs = 4
    val sm = 8
    val md = 12
    val lg = 16
    val xl = 24
    val xxl = 32
}

/** Direct port of `AppRadius` (app_spacing.dart). */
object AdGagRadius {
    val sm = 8
    val md = 12
    val lg = 16
    val pill = 999
}

private val AdGagTypography = Typography(
    headlineSmall = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.sp),
    titleLarge = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.SemiBold),
    titleMedium = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Normal),
    bodyMedium = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Normal),
    labelLarge = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.2.sp),
    labelMedium = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.4.sp),
    labelSmall = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.4.sp),
)

/**
 * Dark is this screen's only presentation — matches the Flutter app's
 * own stance that dark is "the primary video-feed presentation"
 * (CLAUDE.md section 35), and a full-bleed video editor is exactly that
 * kind of surface. `isSystemInDarkTheme()` is read but not branched on;
 * kept as a documented, deliberate choice rather than silently ignoring
 * system theme.
 */
@Composable
fun AdGagEditorTheme(content: @Composable () -> Unit) {
    isSystemInDarkTheme() // Deliberately not branched on — see doc comment above.
    val colorScheme = darkColorScheme(
        primary = AdGagColors.GradientPink,
        onPrimary = Color.White,
        secondary = AdGagColors.GradientBlue,
        onSecondary = Color.White,
        background = AdGagColors.Background,
        onBackground = AdGagColors.OnBackground,
        surface = AdGagColors.Surface,
        onSurface = AdGagColors.OnBackground,
        surfaceVariant = AdGagColors.SurfaceElevated,
        error = AdGagColors.Danger,
        onError = Color.White,
    )
    MaterialTheme(colorScheme = colorScheme, typography = AdGagTypography, content = content)
}
