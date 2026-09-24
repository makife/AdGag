import "dart:async";
import "dart:io";
import "dart:typed_data" show ByteData;

import "package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart";
import "package:ffmpeg_kit_flutter_new_video/ffmpeg_session.dart";
import "package:ffmpeg_kit_flutter_new_video/return_code.dart";
import "package:ffmpeg_kit_flutter_new_video/statistics.dart";
import "package:flutter/services.dart" show rootBundle;
import "package:path_provider/path_provider.dart";

import "../../features/create_ad/domain/video_project.dart";
import "../utils/app_logger.dart";
import "video_export_service.dart";
import "video_filter_graph_builder.dart";

/// [VideoExportService] backed by `ffmpeg_kit_flutter_new_video` (LGPL-3.0
/// — the "video" tier of the `sk3llo/ffmpeg_kit_flutter` fork, verified
/// live against pub.dev before pinning: not the discontinued original
/// `ffmpeg_kit_flutter`, and not a `-gpl` variant. See pubspec.yaml's
/// comment on this dependency for the full verification trail.
///
/// Encodes with the platform's hardware H.264 encoder (`h264_mediacodec`
/// on Android, `h264_videotoolbox` on iOS) rather than the GPL-only
/// software `libx264` — this is what actually keeps the app's own build
/// license-clean, not just which FFmpeg package is chosen.
final class FfmpegVideoExportService implements VideoExportService {
  final StreamController<double> _progressController = StreamController<double>.broadcast();
  final _log = AppLogger.named("FfmpegVideoExportService");
  FFmpegSession? _activeSession;

  @override
  Stream<double> get progress => _progressController.stream;

  String get _videoEncoder {
    if (Platform.isAndroid) {
      return "h264_mediacodec";
    }
    if (Platform.isIOS) {
      return "h264_videotoolbox";
    }
    // Desktop/other: no vetted hardware path here yet — mpeg4 keeps this
    // functional (if slow) rather than throwing, per the spec's own
    // fallback. Not expected to be hit on the app's actual target
    // platforms (Android/iOS).
    return "mpeg4";
  }

  /// FFmpeg's `drawtext` filter needs a real font *file* on disk — Android
  /// has no fontconfig-discoverable "Sans" family the way desktop Linux
  /// does, so relying on a bare family name fails with "Cannot find a
  /// valid font for the family Sans" (confirmed live, via a user's actual
  /// device — a bundled TTF, extracted once to a real path, is the fix,
  /// not a font-family-name tweak). One entry per [TextFontFamily]
  /// (distinct typefaces, not size/weight variants of one font — see
  /// that enum's own doc comment), cached after first extraction since
  /// the bytes never change between exports; only the families a given
  /// project's overlays actually use get extracted, not all five every
  /// time.
  final Map<TextFontFamily, String> _fontFilePaths = <TextFontFamily, String>{};

  Future<String> _ensureFontFile(TextFontFamily family) async {
    final String? cached = _fontFilePaths[family];
    if (cached != null && File(cached).existsSync()) {
      return cached;
    }
    final ByteData data = await rootBundle.load(family.assetPath);
    final Directory tempDir = await getTemporaryDirectory();
    final File file = File("${tempDir.path}/adgag_drawtext_font_${family.name}.ttf");
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    _fontFilePaths[family] = file.path;
    return file.path;
  }

  @override
  Future<String> export(VideoProject project) async {
    final Directory tempDir = await getTemporaryDirectory();
    final String outputPath =
        "${tempDir.path}/adgag_export_${DateTime.now().millisecondsSinceEpoch}.mp4";

    final Set<TextFontFamily> familiesUsed = <TextFontFamily>{
      for (final VideoOverlay overlay in project.overlays)
        if (overlay is TextOverlay) overlay.fontFamily,
    };
    // Text is optional, but drawtext=fontfile= is still required
    // plumbing whenever the filter graph builder needs *a* font path to
    // reference (e.g. if a future filter needs one even without text) —
    // always resolve at least the default so callers never see a null.
    if (familiesUsed.isEmpty) {
      familiesUsed.add(TextFontFamily.classic);
    }
    final Map<TextFontFamily, String> fontFilePaths = <TextFontFamily, String>{
      for (final TextFontFamily family in familiesUsed) family: await _ensureFontFile(family),
    };

    final List<String> args = VideoFilterGraphBuilder.build(
      project: project,
      outputPath: outputPath,
      videoEncoder: _videoEncoder,
      fontFilePaths: fontFilePaths,
    );

    final int totalMs = project.trimmedDuration.inMilliseconds;
    final Completer<String> completer = Completer<String>();

    _activeSession = await FFmpegKit.executeWithArgumentsAsync(
      args,
      (FFmpegSession session) async {
        _activeSession = null;
        final ReturnCode? code = await session.getReturnCode();
        if (ReturnCode.isSuccess(code)) {
          _progressController.add(1.0);
          if (!completer.isCompleted) {
            completer.complete(outputPath);
          }
        } else if (ReturnCode.isCancel(code)) {
          if (!completer.isCompleted) {
            completer.completeError(StateError("Export cancelled"));
          }
        } else {
          final String? logs = await session.getAllLogsAsString();
          _log.warning("FFmpeg export failed (code: $code)", logs);
          if (!completer.isCompleted) {
            completer.completeError(StateError("Export failed: ${_summarize(logs) ?? code}"));
          }
        }
      },
      null,
      (Statistics stats) {
        if (totalMs > 0) {
          final double fraction = (stats.getTime() / totalMs).clamp(0.0, 1.0);
          _progressController.add(fraction);
        }
      },
    );

    return completer.future;
  }

  /// FFmpeg's full log starts with a long build-configuration banner
  /// (compiler flags, enabled libraries, paths — hundreds of characters
  /// before anything about *this* run) followed by the actual per-run
  /// output; the real failure reason is always near the end, never the
  /// start. Showing the raw log to a user surfaces the banner and
  /// nothing useful — this keeps just the last handful of non-empty
  /// lines, which is where FFmpeg actually reports why a run failed.
  String? _summarize(String? logs) {
    if (logs == null || logs.trim().isEmpty) {
      return null;
    }
    final List<String> lines = logs.split("\n").map((String l) => l.trim()).where((String l) => l.isNotEmpty).toList();
    final List<String> tail = lines.length > 12 ? lines.sublist(lines.length - 12) : lines;
    return tail.join("\n");
  }

  @override
  Future<void> cancel() async {
    final int? sessionId = _activeSession?.getSessionId();
    if (sessionId != null) {
      await FFmpegKit.cancel(sessionId);
    }
  }
}
