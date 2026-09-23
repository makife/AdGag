import "../../features/create_ad/domain/video_project.dart";

/// Renders a [VideoProject] (trim + speed zones + background audio +
/// overlays) into a single output video (CLAUDE.md section 4/38's editing
/// step, timeline-export half). Distinct from [VideoEditorService]
/// (core/media/video_editor_service.dart), which stays the simple
/// single-operation trim/speed/rotate/flip/audio path backed by
/// `easy_video_editor` for the common case that doesn't need a multi-track
/// timeline at all — this is the "comprehensive editor" path in the
/// production-flow sense: heavier, native FFmpeg-backed, used once the
/// user actually adds a speed zone, background music, or an overlay.
abstract interface class VideoExportService {
  /// Emits 0.0-1.0 while a render is in progress. Broadcast — safe for a
  /// UI widget to listen to across rebuilds without missing the start.
  Stream<double> get progress;

  /// Renders [project] to a new .mp4 file and returns its path. Does not
  /// modify [project.videoPath]. Throws if the underlying FFmpeg session
  /// fails or is cancelled — callers should surface `error.toString()`,
  /// the same pattern as [VideoEditorService.apply].
  Future<String> export(VideoProject project);

  /// Cancels the in-flight [export] call, if any.
  Future<void> cancel();
}
