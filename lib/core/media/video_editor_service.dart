/// Rotation step, always applied clockwise (CLAUDE.md section 4: keep the
/// control simple — one "rotate" button that cycles 90/180/270, not a
/// free-angle dial).
enum AppVideoRotation { none, degrees90, degrees180, degrees270 }

/// Mirror axis for a flip operation.
enum AppFlipDirection { none, horizontal, vertical }

/// A general (but still intentionally small) local video editing pipeline —
/// the expansion of what was a trim-only [VideoTrimmer]. Every operation
/// here is backed by `easy_video_editor`'s native (on-device, no server
/// round trip) implementation; nothing here does text/graphic overlay
/// compositing, which that package doesn't support (see
/// EasyVideoEditorService's doc comment for why that's a separate,
/// larger piece of work).
abstract interface class VideoEditorService {
  /// Applies every non-default operation in [request] to [sourcePath] in a
  /// single chained export and returns the output file path. Does not
  /// modify [sourcePath].
  Future<String> apply(
    VideoEditRequest request, {
    void Function(double progress)? onProgress,
  });
}

final class VideoEditRequest {
  const VideoEditRequest({
    required this.sourcePath,
    required this.trimStart,
    required this.trimEnd,
    this.speed = 1.0,
    this.rotation = AppVideoRotation.none,
    this.flip = AppFlipDirection.none,
    this.removeAudio = false,
  });

  final String sourcePath;
  final Duration trimStart;
  final Duration trimEnd;

  /// Playback speed multiplier — e.g. 0.5 for slow motion, 2.0 for fast
  /// forward. 1.0 (the default) applies no speed operation.
  final double speed;
  final AppVideoRotation rotation;
  final AppFlipDirection flip;
  final bool removeAudio;

  bool get hasAnyEdit =>
      speed != 1.0 || rotation != AppVideoRotation.none || flip != AppFlipDirection.none || removeAudio;
}
