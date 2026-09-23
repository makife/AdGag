import "package:easy_video_editor/easy_video_editor.dart";

import "video_trimmer.dart";

final class EasyVideoEditorTrimmer implements VideoTrimmer {
  @override
  Future<String> trim({
    required String sourcePath,
    required Duration start,
    required Duration end,
    void Function(double progress)? onProgress,
  }) async {
    final VideoEditorBuilder builder = VideoEditorBuilder(videoPath: sourcePath).trim(
      startTimeMs: start.inMilliseconds,
      endTimeMs: end.inMilliseconds,
    );

    final String? outputPath = await builder.export(onProgress: onProgress);
    if (outputPath == null) {
      throw StateError("Video trim produced no output file");
    }
    return outputPath;
  }
}
