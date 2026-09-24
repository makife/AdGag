import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/media/video_editor_service.dart" show AppFlipDirection, AppVideoRotation;
import "../../domain/video_project.dart";

/// Owns the *single* [VideoProject] a `TrimStep` session edits — the
/// preview widgets and the exporter both read this same object, never a
/// parallel copy kept in widget state. Every mutating method here pushes
/// the pre-edit project onto an undo stack first, so undo/redo falls out
/// of the fact that [VideoProject] is already an immutable value type —
/// no command objects or diffing needed, just snapshots.
///
/// `null` state means "not yet initialized" (before [init] is called
/// with the actual captured clip) — `TrimStep` treats that the same way
/// it already treats "video controller not yet initialized," not as an
/// error state.
final class EditorController extends AutoDisposeNotifier<VideoProject?> {
  @override
  VideoProject? build() => null;

  final List<VideoProject> _undoStack = <VideoProject>[];
  final List<VideoProject> _redoStack = <VideoProject>[];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Starts a fresh editing session on [project] — clears any undo/redo
  /// history from a previous session, since `TrimStep` is `autoDispose`
  /// but this provider (kept alive across the whole AD-tab flow so
  /// Retake -> re-capture -> back-to-trim doesn't lose an in-progress
  /// edit... except Retake *does* intentionally discard everything, so
  /// starting clean here is correct either way).
  void init(VideoProject project) {
    _undoStack.clear();
    _redoStack.clear();
    state = project;
  }

  void _apply(VideoProject Function(VideoProject current) mutate) {
    final VideoProject? current = state;
    if (current == null) {
      return;
    }
    _undoStack.add(current);
    _redoStack.clear();
    state = mutate(current);
  }

  void undo() {
    final VideoProject? current = state;
    if (current == null || _undoStack.isEmpty) {
      return;
    }
    _redoStack.add(current);
    state = _undoStack.removeLast();
  }

  void redo() {
    final VideoProject? current = state;
    if (current == null || _redoStack.isEmpty) {
      return;
    }
    _undoStack.add(current);
    state = _redoStack.removeLast();
  }

  /// Clears every edit back to an untouched clip (distinct from Retake,
  /// which discards the capture itself) — still one undo-able step, so
  /// a user who hits Reset by mistake can undo it.
  void resetToDefaults(Duration initialTrimEnd) {
    final VideoProject? current = state;
    if (current == null) {
      return;
    }
    _apply((_) => VideoProject(videoPath: current.videoPath, trimStart: Duration.zero, trimEnd: initialTrimEnd));
  }

  void setTrim({required Duration start, required Duration end}) =>
      _apply((VideoProject p) => p.withTrim(start: start, end: end));

  void setRotation(AppVideoRotation value) => _apply((VideoProject p) => p.withRotation(value));

  void setFlip(AppFlipDirection value) => _apply((VideoProject p) => p.withFlip(value));

  void setRemoveAudio(bool value) => _apply((VideoProject p) => p.withRemoveAudio(value: value));

  void setColorFilter(AppColorFilter value) => _apply((VideoProject p) => p.withColorFilter(value));

  void addSpeedZone(SpeedZone zone) => _apply((VideoProject p) => p.withSpeedZone(zone));

  void removeSpeedZone(SpeedZone zone) => _apply((VideoProject p) => p.withoutSpeedZone(zone));

  void resizeSpeedZone(SpeedZone oldZone, SpeedZone updated) =>
      _apply((VideoProject p) => p.replaceSpeedZone(oldZone, updated));

  void setBgAudio(BackgroundAudio? audio) => _apply((VideoProject p) => p.withBgAudio(audio));

  void addOverlay(VideoOverlay overlay) => _apply((VideoProject p) => p.withOverlay(overlay));

  void removeOverlay(String overlayId) => _apply((VideoProject p) => p.withoutOverlay(overlayId));

  void updateOverlay(VideoOverlay updated) => _apply((VideoProject p) => p.updateOverlay(updated));
}

/// `autoDispose`: a fresh session (and a fresh undo history) every time
/// `TrimStep` mounts, rather than a singleton that could leak one
/// session's edits/history into the next capture.
final AutoDisposeNotifierProvider<EditorController, VideoProject?> editorControllerProvider =
    AutoDisposeNotifierProvider<EditorController, VideoProject?>(EditorController.new);
