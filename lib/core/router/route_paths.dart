import "dart:async" show unawaited;

import "package:flutter/widgets.dart";
import "package:go_router/go_router.dart";

/// Centralized route paths/names. Screens navigate via these constants (or
/// the [BuildContext] helpers below) rather than hand-typed strings, so a
/// path can change in one place. Deep links (section 33/54) resolve to
/// these same paths.
abstract final class RoutePaths {
  static const String onboarding = "/onboarding";
  static const String signIn = "/sign-in";
  static const String signUp = "/sign-up";

  static const String home = "/home";
  static const String market = "/market";
  static const String create = "/create";
  static const String activity = "/activity";
  static const String profile = "/profile";

  static const String subject = "/subjects/:subjectId";
  static String subjectOf(String subjectId) => "/subjects/$subjectId";

  static const String dailyAd = "/daily-ad";

  static const String userProfile = "/u/:username";
  static String userProfileOf(String username) => "/u/$username";

  static const String editProfile = "/profile/edit";

  /// Matches the share link shape ShareButton builds
  /// (`https://<host>/ad/<id>` — see share_button.dart). Universal/App
  /// Links hand the OS-resolved path straight to go_router; see README.md
  /// > Deep Links for the platform-side association-file setup this still
  /// needs before an external tap actually opens the app.
  static const String adDetail = "/ad/:adId";
  static String adDetailOf(String adId) => "/ad/$adId";
}

extension AppNavigation on BuildContext {
  void goTo(String path) => GoRouter.of(this).go(path);
  Future<T?> pushTo<T>(String path) => GoRouter.of(this).push<T>(path);
  void pushReplacementTo(String path) => unawaited(GoRouter.of(this).pushReplacement(path));
}
