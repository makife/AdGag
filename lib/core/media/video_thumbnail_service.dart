/// Generates a filmstrip of real decoded frames from a video file — the
/// creation editor's timeline (`TrimStep`'s `_Timeline`) shows these
/// instead of a flat placeholder bar. Abstracted the same way
/// [VideoExportService] is, even though only one implementation exists
/// today: the timeline widget shouldn't know or care that FFmpeg is what
/// actually decodes the frames.
abstract interface class VideoThumbnailService {
  /// Extracts up to [count] evenly-spaced JPEG thumbnails covering the
  /// first [duration] of [videoPath], each scaled to [maxWidth]px wide.
  /// Returns their file paths in chronological order — fewer than
  /// [count] (including empty) on any failure, never a thrown exception,
  /// since a missing filmstrip should degrade to the plain lane
  /// background, not break the editor.
  Future<List<String>> generateThumbnails({
    required String videoPath,
    required Duration duration,
    required int count,
    int maxWidth = 96,
  });
}
