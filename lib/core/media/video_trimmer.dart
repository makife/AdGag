/// Lightweight trim only (CLAUDE.md section 4: "Do NOT build a CapCut
/// clone"). One operation — cut to a start/end window — not a general
/// editing pipeline; see [EasyVideoEditorTrimmer] for the implementation.
abstract interface class VideoTrimmer {
  /// Returns the path to a new trimmed file. Does not modify [sourcePath].
  Future<String> trim({
    required String sourcePath,
    required Duration start,
    required Duration end,
    void Function(double progress)? onProgress,
  });
}
