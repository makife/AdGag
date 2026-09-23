import "video_constraints.dart";

/// A recorded/imported/trimmed video still sitting on local disk, before
/// any upload has started (CLAUDE.md section 39/40 — drafts should
/// "retain local draft when possible").
final class LocalVideoDraft {
  const LocalVideoDraft({required this.filePath, required this.duration});

  final String filePath;
  final Duration duration;

  bool get isWithinConstraints =>
      duration >= VideoConstraints.min && duration <= VideoConstraints.max;
}
