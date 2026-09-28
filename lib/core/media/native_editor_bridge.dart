import "package:flutter/services.dart";

/// What a native editor session ended with (a `null` from
/// [NativeEditorBridge.openEditor] means the user backed out).
sealed class NativeEditorOutcome {
  const NativeEditorOutcome();
}

/// The Ad was exported — the file's path and its duration, as reported
/// by the native side (authoritative: the export already ran).
final class NativeEditorExported extends NativeEditorOutcome {
  const NativeEditorExported({required this.filePath, required this.durationMs});
  final String filePath;
  final int durationMs;
}

/// The user tapped the timeline's "+" to record another clip. [state] is
/// the native editor's own session (opaque JSON — never parsed here),
/// handed straight back to [NativeEditorBridge.openEditor] afterwards;
/// [remainingMs] is how much of the 30s cap is left to record.
final class NativeEditorAddClipRequested extends NativeEditorOutcome {
  const NativeEditorAddClipRequested({required this.state, required this.remainingMs});
  final String state;
  final int remainingMs;
}

/// Bridges to the per-platform NATIVE editor screen (Kotlin + Media3 on
/// Android; Swift + AVFoundation on iOS) — launched as a separate native
/// screen via a platform channel, not a Flutter widget.
///
/// Why it's native at all: the old Flutter editor kept two independent
/// `VideoPlayerController`s (video + music), each with its own clock, and
/// no amount of resync patching fully removed drift — see the CLAUDE.md
/// checkpoint entries from 2026-09-25. The native preview plays video and
/// music through ONE player / one clock.
///
/// Recording extra clips uses Flutter's own camera: the native editor
/// closes with [NativeEditorAddClipRequested], the camera records, and
/// the editor is reopened with that state plus the new clip.
abstract final class NativeEditorBridge {
  static const MethodChannel _channel = MethodChannel("com.adgag.adgag/native_editor");

  /// Opens the native editor — either fresh for [videoPath], or resuming
  /// a previous session's [state] (optionally appending [newClipPath]).
  /// Returns `null` if the user cancelled (backed out without exporting)
  /// — not an error. Throws [PlatformException] for a genuine native-side
  /// failure (the caller should surface it, per this app's "never
  /// silently fail" rule).
  static Future<NativeEditorOutcome?> openEditor({
    String? videoPath,
    String? state,
    String? newClipPath,
    int rotationDegrees = 0,
    String languageCode = "en",
  }) async {
    assert(videoPath != null || state != null, "openEditor needs a videoPath or a state to resume");
    final Object? raw = await _channel.invokeMethod<Object?>("openEditor", <String, Object?>{
      "videoPath": videoPath,
      "state": state,
      "newClipPath": newClipPath,
      "rotationDegrees": rotationDegrees,
      // The language the app is showing; the native editor uses the same.
      "languageCode": languageCode,
    });
    if (raw == null) {
      return null;
    }
    final Map<Object?, Object?> map = raw as Map<Object?, Object?>;
    if (map["action"] == "addClip") {
      return NativeEditorAddClipRequested(
        state: map["state"]! as String,
        remainingMs: (map["remainingMs"]! as num).toInt(),
      );
    }
    return NativeEditorExported(
      filePath: map["path"]! as String,
      durationMs: (map["durationMs"]! as num).toInt(),
    );
  }

  /// Reads and clears whatever checkpoint log survived on disk from the
  /// last native editor attempt — the Android side's diagnostic for a
  /// native (not JVM) crash, which kills the whole process and so can
  /// only be read on the NEXT launch. Returns `null` if there's nothing
  /// (or on iOS, which doesn't implement this diagnostic).
  static Future<String?> readAndClearDebugLog() async {
    try {
      return await _channel.invokeMethod<String?>("readAndClearNativeEditorDebugLog");
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
