import "package:flutter/material.dart";

import "../localization/generated/app_localizations.dart";
import "../theme/app_colors.dart";

/// Shown only while the initial auth session is being resolved. Kept
/// deliberately brief and static — no animation dependency — since it's on
/// the critical cold-start path (section 50: time from install -> first Ad).
///
/// The brand mark (assets/branding/AdGagLogo.png — icon + "AdGag" wordmark,
/// no frame, transparent) with the slogan under it as real text, so it
/// follows the app's language.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.darkBackground,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: BrandLockup(tagline: AppLocalizations.of(context).appTagline),
        ),
      ),
    );
  }
}

/// The AdGag logo with the slogan under it — splash and the first onboarding
/// slide. Meant for a dark background (the wordmark's "Gag" is white).
class BrandLockup extends StatelessWidget {
  const BrandLockup({required this.tagline, this.logoWidth = 260, this.textAlign = TextAlign.center, super.key});

  final String tagline;
  final double logoWidth;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: textAlign == TextAlign.center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: <Widget>[
        Image.asset("assets/branding/AdGagLogo.png", width: logoWidth, semanticLabel: "AdGag"),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            tagline,
            textAlign: textAlign,
            style: const TextStyle(
              color: AppColors.darkOnBackground,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.35,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}
