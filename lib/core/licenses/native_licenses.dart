import "package:flutter/foundation.dart";
import "package:flutter/services.dart";

/// Adds the licences of what the native editors ship to Flutter's
/// [LicenseRegistry], so Settings > About > Open source libraries
/// (`showLicensePage`) lists them next to the Dart packages it already
/// knows about: the 39 caption fonts (SIL OFL 1.1 / Apache 2.0), Google's
/// Noto Animated Emoji stickers (CC BY 4.0 — attribution required), and
/// AndroidX Media3 / Jetpack Compose (Apache 2.0).
///
/// Texts live in assets/licenses/ (copies of the native asset folders).
/// Collected lazily — the registry only runs this when the page opens.
void registerNativeLicenses() {
  LicenseRegistry.addLicense(_collect);
}

const String _fontsDir = "assets/licenses/fonts/";

Stream<LicenseEntry> _collect() async* {
  final AssetManifest manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final List<String> fontFiles = manifest.listAssets().where((String a) => a.startsWith(_fontsDir)).toList()..sort();
  String? apacheText;
  for (final String path in fontFiles) {
    final String text = await rootBundle.loadString(path);
    // "anton-OFL.txt" -> "anton"
    final String id = path.substring(_fontsDir.length).split("-").first;
    yield LicenseEntryWithLineBreaks(<String>["Font: $id"], text);
    if (path.endsWith("-LICENSE.txt")) {
      apacheText ??= text; // the non-OFL fonts are Apache 2.0
    }
  }

  yield LicenseEntryWithLineBreaks(
    <String>["Noto Animated Emoji"],
    await rootBundle.loadString("assets/licenses/noto-animated-emoji.txt"),
  );

  if (apacheText != null) {
    yield LicenseEntryWithLineBreaks(
      <String>["AndroidX Media3", "Jetpack Compose"],
      "Copyright The Android Open Source Project\n\n$apacheText",
    );
  }
}
