import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:go_router/go_router.dart";

import "../../features/auth/presentation/providers/auth_providers.dart";
import "../../features/auth/presentation/screens/onboarding_screen.dart";
import "../../features/auth/presentation/screens/sign_in_screen.dart";
import "../../features/auth/presentation/screens/sign_up_screen.dart";
import "../../features/create_ad/presentation/screens/create_ad_screen.dart";
import "../../features/feed/presentation/screens/feed_screen.dart";
import "../../features/market/presentation/screens/market_screen.dart";
import "../../features/notifications/presentation/activity_screen.dart";
import "../../features/profile/presentation/screens/profile_screen.dart";
import "../../features/profile/presentation/screens/public_profile_screen.dart";
import "../../features/subjects/presentation/screens/subject_screen.dart";
import "app_shell.dart";
import "route_paths.dart";

/// Bridges the Riverpod auth stream to go_router's [Listenable]-based
/// `refreshListenable`, so the router re-evaluates `redirect` whenever auth
/// state changes (sign in, sign out, token refresh) without polling.
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(currentAppUserProvider, (previous, next) {
      notifyListeners();
    });
  }
}

final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((ref) {
  final _RouterRefreshNotifier refresh = _RouterRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: RoutePaths.onboarding,
    debugLogDiagnostics: kDebugMode,
    refreshListenable: refresh,
    redirect: (BuildContext context, GoRouterState state) {
      final AsyncValue<Object?> userAsync = ref.read(currentAppUserProvider);
      final String location = state.matchedLocation;

      final bool isAuthRoute = location == RoutePaths.onboarding ||
          location == RoutePaths.signIn ||
          location == RoutePaths.signUp;

      // Still resolving the initial session: stay put, splash covers it.
      if (userAsync.isLoading && !userAsync.hasValue) {
        return null;
      }

      final bool signedIn = userAsync.valueOrNull != null;

      if (!signedIn && !isAuthRoute) {
        return RoutePaths.onboarding;
      }
      if (signedIn && isAuthRoute) {
        return RoutePaths.home;
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: RoutePaths.onboarding,
        builder: (BuildContext context, GoRouterState state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: RoutePaths.signIn,
        builder: (BuildContext context, GoRouterState state) => const SignInScreen(),
      ),
      GoRoute(
        path: RoutePaths.signUp,
        builder: (BuildContext context, GoRouterState state) => const SignUpScreen(),
      ),
      GoRoute(
        path: RoutePaths.subject,
        builder: (BuildContext context, GoRouterState state) =>
            SubjectScreen(subjectId: state.pathParameters["subjectId"]!),
      ),
      GoRoute(
        path: RoutePaths.userProfile,
        builder: (BuildContext context, GoRouterState state) =>
            PublicProfileScreen(username: state.pathParameters["username"]!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (BuildContext context, GoRouterState state, StatefulNavigationShell shell) {
          return AppShell(navigationShell: shell);
        },
        branches: <StatefulShellBranch>[
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: RoutePaths.home, builder: (context, state) => const FeedScreen()),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: RoutePaths.market, builder: (context, state) => const MarketScreen()),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: RoutePaths.create, builder: (context, state) => const CreateAdScreen()),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: RoutePaths.activity, builder: (context, state) => const ActivityScreen()),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: RoutePaths.profile, builder: (context, state) => const ProfileScreen()),
          ]),
        ],
      ),
    ],
  );
});
