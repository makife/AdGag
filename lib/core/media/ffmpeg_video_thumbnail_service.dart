import "dart:async";
import "dart:io";

import "package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart";
import "package:ffmpeg_kit_flutter_new_video/ffmpeg_session.dart";
import "package:ffmpeg_kit_flutter_new_video/return_code.dart";
import "package:path_provider/path_provider.dart";

import "video_thumbnail_service.dart";

/// [VideoThumbnailService] backed by the same `ffmpeg_kit_flutter_new_video`
/// dependency [FfmpegVideoExportService] already uses — one real FFmpeg
/// pass with a `select` filter (the standard idiom for "N evenly-spaced
/// frames") rather than N separate `-ss`/`-i` invocations, which would
/// pay FFmpeg's process-startup cost N times over for a handful of small
/// thumbnails.
final class FfmpegVideoThumbnailService implements VideoThumbnailService {
  @override
  Future<List<String>> generateThumbnails({
    required String videoPath,
    required Duration duration,
    required int count,
    int maxWidth = 96,
  }) async {
    if (count <= 0 || duration <= Duration.zero) {
      return const <String>[];
    }

    final Directory tempDir = await getTemporaryDirectory();
    final String prefix = "adgag_thumb_${DateTime.now().millisecondsSinceEpoch}";
    final String outputPattern = "${tempDir.path}/${prefix}_%03d.jpg";
    final double stepSec = (duration.inMilliseconds / 1000.0) / count;

    final List<String> args = <String>[
      "-i", videoPath,
      "-vf",
      "select='isnan(prev_selected_t)+gte(t-prev_selected_t\\,${stepSec.toStringAsFixed(3)})',"
          "scale=$maxWidth:-1",
      "-vsync", "vfr",
      "-frames:v", "$count",
      "-y",
      outputPattern,
    ];

    final Completer<List<String>> completer = Completer<List<String>>();
    unawaited(
      FFmpegKit.executeWithArgumentsAsync(args, (FFmpegSession session) async {
        final ReturnCode? code = await session.getReturnCode();
        if (!ReturnCode.isSuccess(code)) {
          if (!completer.isCompleted) {
            completer.complete(const <String>[]);
          }
          return;
        }
        final List<String> paths = <String>[
          for (int i = 1; i <= count; i++) "${tempDir.path}/${prefix}_${i.toString().padLeft(3, '0')}.jpg",
        ];
        final List<String> existing = paths.where((String p) => File(p).existsSync()).toList();
        if (!completer.isCompleted) {
          completer.complete(existing);
        }
      }),
    );
    return completer.future;
  }
}
