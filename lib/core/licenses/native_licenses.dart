import "package:flutter/foundation.dart";
import "package:flutter/services.dart";

/// Adds the licences of what the native editors ship to Flutter's
/// [LicenseRegistry], so Settings > About > Open source libraries
/// (`showLicensePage`) lists them next to the Dart packages it already
/// knows about: the 39 caption fonts (SIL OFL 1.1 / Apache 2.0), Google's
/// Noto Animated Emoji stickers (CC BY 4.0 — attribution required),
/// AndroidX Media3 / Jetpack Compose / CameraX effects (Apache 2.0), and
/// Google ML Kit face detection (the camera's live face effects).
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

  yield LicenseEntryWithLineBreaks(
    <String>["Sound effects (Freesound, Kenney)"],
    await rootBundle.loadString("assets/licenses/sound-effects.txt"),
  );

  if (apacheText != null) {
    yield LicenseEntryWithLineBreaks(
      <String>["AndroidX Media3", "Jetpack Compose", "AndroidX CameraX (effects, ML Kit vision)"],
      "Copyright The Android Open Source Project\n\n$apacheText",
    );
  }

  // The live face effects' face detection. ML Kit is distributed under
  // Google's ML Kit terms rather than an open-source licence; it runs fully
  // on the device (no face data leaves the phone).
  yield const LicenseEntryWithLineBreaks(
    <String>["Google ML Kit Face Detection"],
    "Face detection for the live face effects is provided by Google ML Kit "
    "(com.google.mlkit:face-detection), used under the ML Kit Terms of Service: "
    "https://developers.google.com/ml-kit/terms\n\n"
    "Detection runs entirely on the device. AdGag does not store or send any face data.",
  );
}
