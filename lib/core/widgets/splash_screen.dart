import "package:flutter/material.dart";

import "../theme/app_colors.dart";

/// Shown only while the initial auth session is being resolved. Kept
/// deliberately brief and static — no animation dependency — since it's on
/// the critical cold-start path (section 50: time from install -> first Ad).
///
/// Uses the actual brand lockup image (assets/branding/AdGag.png — icon +
/// "AdGag" wordmark + tagline, exactly as designed) rather than
/// recreating the wordmark with a TextStyle/ShaderMask approximation.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.darkBackground,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 64),
          child: Image.asset("assets/branding/AdGag.png"),
        ),
      ),
    );
  }
}
