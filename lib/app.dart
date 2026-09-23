import "package:flutter/material.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:go_router/go_router.dart";

import "core/localization/generated/app_localizations.dart";
import "core/router/app_router.dart";
import "core/theme/app_theme.dart";
import "core/widgets/splash_screen.dart";
import "features/auth/presentation/providers/auth_providers.dart";

class AdGagApp extends ConsumerWidget {
  const AdGagApp({super.key});

  static const List<Locale> supportedLocales = <Locale>[Locale("en"), Locale("tr")];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Object?> initialUser = ref.watch(currentAppUserProvider);

    // Keep a full MaterialApp mounted at every stage (including the very
    // first auth check) so Theme/Directionality/Localizations are always
    // available — avoids "no MaterialLocalizations found" edge cases from
    // conditionally swapping in a bare widget.
    if (initialUser.isLoading && !initialUser.hasValue) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: SplashScreen(),
      );
    }

    final GoRouter router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: "AdGag",
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
      supportedLocales: supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
