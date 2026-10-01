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
  static const String accountConfirmed = "/welcome";

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

  /// Followers / Following lists; `?tab=following` opens the second tab.
  static const String userFollows = "/u/:username/follows";
  static String userFollowsOf(String username, {bool following = false}) =>
      "/u/$username/follows${following ? '?tab=following' : ''}";

  static const String editProfile = "/profile/edit";

  static const String settings = "/settings";
  static const String settingsAccount = "/settings/account";
  static const String settingsBlocked = "/settings/blocked";
  static const String settingsAbout = "/settings/about";
  static const String settingsNotifications = "/settings/notifications";

  /// Matches the share link shape ShareButton builds
  /// (`https://<host>/ad/<id>` — see share_button.dart). Universal/App
  /// Links hand the OS-resolved path straight to go_router; see README.md
  /// > Deep Links for the platform-side association-file setup this still
  /// needs before an external tap actually opens the app.
  static const String adDetail = "/ad/:adId";
  static String adDetailOf(String adId) => "/ad/$adId";

  /// Ads made with AD THIS from one Ad.
  static const String adThisChain = "/ad/:adId/ad-this";
  static String adThisChainOf(String adId) => "/ad/$adId/ad-this";
}

extension AppNavigation on BuildContext {
  void goTo(String path) => GoRouter.of(this).go(path);
  Future<T?> pushTo<T>(String path) => GoRouter.of(this).push<T>(path);
  void pushReplacementTo(String path) => unawaited(GoRouter.of(this).pushReplacement(path));
}
