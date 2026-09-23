import "package:flutter/material.dart";

import "../theme/app_colors.dart";

/// Shown only while the initial auth session is being resolved. Kept
/// deliberately brief and static — no animation dependency — since it's on
/// the critical cold-start path (section 50: time from install -> first Ad).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.darkBackground,
      child: Center(
        child: ShaderMask(
          shaderCallback: (Rect bounds) => AppColors.brandGradient.createShader(bounds),
          child: const Text(
            "AdGag",
            style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}
