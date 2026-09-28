import "dart:io";

import "package:flutter/services.dart";

import "local_video_prober.dart";
import "video_player_local_prober.dart";

/// Reads a local video's duration from its container METADATA on Android
/// (MainActivity's `probeDurationMs` — MediaMetadataRetriever, no decoder).
/// The video_player way initializes a hardware decoder just to read the
/// duration, and that failed for a 1080p HEVC gallery video
/// ("MediaCodecVideoRenderer error ... format_supported=YES" — user report).
/// Other platforms, or if the metadata can't be read, fall back to it.
final class NativeLocalProber implements LocalVideoProber {
  static const MethodChannel _channel = MethodChannel("com.adgag.adgag/native_editor");
  final LocalVideoProber _fallback = VideoPlayerLocalProber();

  @override
  Future<Duration> probeDuration(String filePath) async {
    if (Platform.isAndroid) {
      try {
        final int? ms = await _channel.invokeMethod<int>("probeDurationMs", <String, Object?>{"path": filePath});
        if (ms != null && ms > 0) {
          return Duration(milliseconds: ms);
        }
      } on PlatformException {
        // Fall through to the player-based probe.
      }
    }
    return _fallback.probeDuration(filePath);
  }
}
