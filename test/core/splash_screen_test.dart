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
  testWidgets("splash shows the slogan in the app's language", (WidgetTester tester) async {
    await tester.pumpWidget(_app(const Locale("tr")));
    await tester.pumpAndSettle();
    expect(find.text("Her şeyin reklam olduğu sosyal ağ."), findsOneWidget);

    await tester.pumpWidget(_app(const Locale("en")));
    await tester.pumpAndSettle();
    expect(find.text("The social network where everything is an ad."), findsOneWidget);
    expect(find.bySemanticsLabel("AdGag"), findsOneWidget);
  });
}
