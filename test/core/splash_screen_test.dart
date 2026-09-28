import "package:adgag/core/localization/generated/app_localizations.dart";
import "package:adgag/core/widgets/splash_screen.dart";
import "package:flutter/material.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:flutter_test/flutter_test.dart";

Widget _app(Locale locale) => MaterialApp(
      locale: locale,
      supportedLocales: const <Locale>[Locale("en"), Locale("tr")],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SplashScreen(),
    );

void main() {
  testWidgets("splash shows only the logo, no slogan", (WidgetTester tester) async {
    await tester.pumpWidget(_app(const Locale("tr")));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel("AdGag"), findsOneWidget);
    expect(find.text("Her şeyin reklam olduğu sosyal ağ."), findsNothing);
  });

  testWidgets("the brand lockup shows the slogan in the app's language", (WidgetTester tester) async {
    Widget lockup(Locale locale) => MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home:
              Builder(builder: (BuildContext context) => BrandLockup(tagline: AppLocalizations.of(context).appTagline)),
        );
    await tester.pumpWidget(lockup(const Locale("tr")));
    await tester.pumpAndSettle();
    expect(find.text("Her şeyin reklam olduğu sosyal ağ."), findsOneWidget);
    await tester.pumpWidget(lockup(const Locale("ja")));
    await tester.pumpAndSettle();
    expect(find.text("すべてが広告になるSNS。"), findsOneWidget);
  });
}
