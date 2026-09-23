import "package:easy_video_editor/easy_video_editor.dart";

import "video_editor_service.dart";

/// [VideoEditorService] backed by `easy_video_editor` — the same
/// actively-maintained, native (JNI on Android) package already used for
/// trimming (pubspec.yaml pin verified against pub.dev; see README.md
/// verification log). Its `VideoEditorBuilder` chains operations and
/// exports them in one pass, so trim + speed + rotate + flip + remove-audio
/// all happen as a single native export rather than N intermediate files.
///
/// What this deliberately does NOT do: burn text, stickers, or GIFs into
/// the video. `easy_video_editor` has no compositing/overlay API — doing
/// that would mean either a GPL-licensed toolchain (ffmpeg's `drawtext`/
/// `overlay` filters, which carries real App Store/Play Store distribution
/// licensing implications) or a custom native frame-compositing pipeline.
/// That's a separate, materially larger piece of work with its own
/// licensing decision to make first — not something to bolt on silently
/// here. See README.md's editor section for the current status.
final class EasyVideoEditorService implements VideoEditorService {
  @override
  Future<String> apply(
    VideoEditRequest request, {
    void Function(double progress)? onProgress,
  }) async {
    VideoEditorBuilder builder = VideoEditorBuilder(videoPath: request.sourcePath).trim(
      startTimeMs: request.trimStart.inMilliseconds,
      endTimeMs: request.trimEnd.inMilliseconds,
    );

    if (request.speed != 1.0) {
      builder = builder.speed(speed: request.speed);
    }
    final RotationDegree? rotation = switch (request.rotation) {
      AppVideoRotation.none => null,
      AppVideoRotation.degrees90 => RotationDegree.degree90,
      AppVideoRotation.degrees180 => RotationDegree.degree180,
      AppVideoRotation.degrees270 => RotationDegree.degree270,
    };
    if (rotation != null) {
      builder = builder.rotate(degree: rotation);
    }
    final FlipDirection? flip = switch (request.flip) {
      AppFlipDirection.none => null,
      AppFlipDirection.horizontal => FlipDirection.horizontal,
      AppFlipDirection.vertical => FlipDirection.vertical,
    };
    if (flip != null) {
      builder = builder.flip(flipDirection: flip);
    }
    if (request.removeAudio) {
      builder = builder.removeAudio();
    }

    final String? outputPath = await builder.export(onProgress: onProgress);
    if (outputPath == null) {
      throw StateError("Video edit produced no output file");
    }
    return outputPath;
  }
}
