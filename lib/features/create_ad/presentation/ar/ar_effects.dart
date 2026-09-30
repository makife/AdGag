import "package:flutter/services.dart";

import "../../../../core/localization/generated/app_localizations.dart";

/// One live AR face effect. Drawn natively on the camera frames (preview AND
/// recording) — see third_party/camera_android_camerax/.../AdGagAr.kt and
/// ArEffects.kt, which use the same [id]s. Android only for now.
final class ArEffect {
  const ArEffect(this.id, this.emoji);

  final String id;

  /// Picker thumbnail (system emoji — nothing to bundle or license).
  final String emoji;

  String label(AppLocalizations l10n) => switch (id) {
        "sunglasses" => l10n.arSunglasses,
        "nerd" => l10n.arNerd,
        "crown" => l10n.arCrown,
        "flower_crown" => l10n.arFlowerCrown,
        "party" => l10n.arParty,
        "viking" => l10n.arViking,
        "devil" => l10n.arDevil,
        "halo" => l10n.arHalo,
        "cat" => l10n.arCat,
        "bunny" => l10n.arBunny,
        "puppy" => l10n.arPuppy,
        "alien" => l10n.arAlien,
        "heart_eyes" => l10n.arHeartEyes,
        "star_eyes" => l10n.arStarEyes,
        "blush" => l10n.arBlush,
        "tears" => l10n.arTears,
        "hearts" => l10n.arHearts,
        "money_rain" => l10n.arMoneyRain,
        "sparkles" => l10n.arSparkles,
        "rainbow" => l10n.arRainbow,
        "mustache" => l10n.arMustache,
        "clown" => l10n.arClown,
        _ => id,
      };

  /// Picker order: the loop's crowd-pleasers first. The ids must match
  /// ArEffects.kt.
  static const List<ArEffect> all = <ArEffect>[
    ArEffect("sunglasses", "🕶️"),
    ArEffect("crown", "👑"),
    ArEffect("money_rain", "💰"),
    ArEffect("rainbow", "🌈"),
    ArEffect("heart_eyes", "😍"),
    ArEffect("star_eyes", "🤩"),
    ArEffect("hearts", "💕"),
    ArEffect("sparkles", "✨"),
    ArEffect("party", "🥳"),
    ArEffect("flower_crown", "🌸"),
    ArEffect("cat", "🐱"),
    ArEffect("bunny", "🐰"),
    ArEffect("puppy", "🐶"),
    ArEffect("devil", "😈"),
    ArEffect("halo", "😇"),
    ArEffect("alien", "👽"),
    ArEffect("viking", "⚔️"),
    ArEffect("nerd", "🤓"),
    ArEffect("blush", "☺️"),
    ArEffect("tears", "😭"),
    ArEffect("mustache", "🥸"),
    ArEffect("clown", "🤡"),
  ];
}

/// How CameraX wants the AR preview buffer shown (it is GL-processed, so
/// the plugin's own rotation logic doesn't apply to it).
final class ArPreviewInfo {
  const ArPreviewInfo({
    required this.rotationDegrees,
    required this.mirroring,
    required this.hasCameraTransform,
    required this.width,
    required this.height,
  });

  factory ArPreviewInfo.fromMap(Map<Object?, Object?> m) => ArPreviewInfo(
        rotationDegrees: (m["rotationDegrees"] as num?)?.toInt() ?? 0,
        mirroring: m["mirroring"] as bool? ?? false,
        hasCameraTransform: m["hasCameraTransform"] as bool? ?? true,
        width: (m["width"] as num?)?.toDouble() ?? 1,
        height: (m["height"] as num?)?.toDouble() ?? 1,
      );

  /// Clockwise degrees to turn the buffer (then mirror, if [mirroring]).
  final int rotationDegrees;
  final bool mirroring;

  /// True = the texture already carries the camera's own transform (then the
  /// plugin's normal preview widget is right, not this info).
  final bool hasCameraTransform;
  final double width;
  final double height;
}

/// The "adgag/ar" channel of the vendored camera plugin.
abstract final class ArCameraBridge {
  static const MethodChannel _channel = MethodChannel("adgag/ar");

  /// The effect picked for this app session; survives reopening the camera
  /// (e.g. for the next take) until changed.
  static String? selectedEffect;

  /// Tells the native side what to draw. With [id] set BEFORE a camera is
  /// opened, that camera is bound with the AR pipeline.
  static Future<void> setEffect(String? id) async {
    selectedEffect = id;
    await _channel.invokeMethod<void>("setEffect", <String, Object?>{"id": id});
  }

  /// Whether the open camera was bound with the AR pipeline.
  static Future<bool> isPipelineBound() async => await _channel.invokeMethod<bool>("isPipelineBound") ?? false;

  /// The last camera error (with native stack trace) while AR was picked, or
  /// null; reading clears it. For diagnosing device-only failures.
  static Future<String?> lastError() async {
    try {
      return await _channel.invokeMethod<String>("lastError");
    } catch (_) {
      return null;
    }
  }

  /// The preview buffer's transform; null until CameraX has reported it.
  static Future<ArPreviewInfo?> previewInfo() async {
    final Map<Object?, Object?>? m = await _channel.invokeMethod<Map<Object?, Object?>>("previewInfo");
    return m == null ? null : ArPreviewInfo.fromMap(m);
  }
}
