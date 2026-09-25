import "package:flutter/services.dart";

/// Result of a native editor session — the exported file's path and its
/// duration, as reported by the native side (which is authoritative:
/// the export already ran through the native pipeline before this
/// returns, so this is a real measured duration, not an estimate).
final class NativeEditorResult {
  const NativeEditorResult({required this.filePath, required this.durationMs});
  final String filePath;
  final int durationMs;
}

/// Bridges to a per-platform NATIVE editor screen (Kotlin + Media3
/// CompositionPlayer on Android; Swift + AVFoundation on iOS, once
/// built) — launched as a separate native screen via a platform
/// channel, not a Flutter widget.
///
/// Why this exists at all, not just "another editor implementation":
/// AdGag's own Flutter editor kept two independent `VideoPlayerController`s
/// (video + background music), each with its own native clock, and no
/// amount of retry/watchdog patching around periodic re-seeking ever
/// fully eliminated audible drift or stall-recovery glitches — see the
/// project's CLAUDE.md checkpoint entries from 2026-09-25 for the full
/// diagnostic history. A native screen built on Media3's
/// `CompositionPlayer` plays video + background audio through ONE
/// Player instance / ONE native clock, which is structurally immune to
/// that entire class of bug (there is nothing to keep in sync from the
/// outside, because there is only one clock to begin with).
///
/// Phase 1 scope only: playback + trim + one background-music
/// attachment. Text/stickers/filters/speed zones are NOT yet available
/// here — the existing Flutter editor ([TrimStep]) remains the
/// feature-complete production path until later phases land on this
/// native screen too. This bridge is reachable today only from
/// [TrimStep]'s debug menu, not the main creation flow, until phase 1
/// is confirmed working well on a real device.
abstract final class NativeEditorBridge {
  static const MethodChannel _channel = MethodChannel("com.adgag.adgag/native_editor");

  /// Opens the native editor for [videoPath]. Returns `null` if the user
  /// cancelled (backed out without exporting) — not an error, matching
  /// how the rest of the creation flow already treats "user backed out."
  /// Throws [PlatformException] for a genuine native-side failure (the
  /// caller should surface this, not silently swallow it, per this
  /// app's "never silently fail" rule).
  static Future<NativeEditorResult?> openEditor(String videoPath) async {
    final Object? raw = await _channel.invokeMethod<Object?>("openEditor", <String, Object?>{
      "videoPath": videoPath,
    });
    if (raw == null) {
      return null;
    }
    final Map<Object?, Object?> map = raw as Map<Object?, Object?>;
    return NativeEditorResult(
      filePath: map["path"]! as String,
      durationMs: (map["durationMs"]! as num).toInt(),
    );
  }
}
