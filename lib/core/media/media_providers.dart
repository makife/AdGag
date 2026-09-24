import "dart:async" show unawaited;

import "package:flutter_riverpod/flutter_riverpod.dart";

import "easy_video_editor_service.dart";
import "ffmpeg_video_export_service.dart";
import "ffmpeg_video_thumbnail_service.dart";
import "local_video_prober.dart";
import "video_editor_service.dart";
import "video_export_service.dart";
import "video_player_local_prober.dart";
import "video_thumbnail_service.dart";

final Provider<VideoEditorService> videoEditorServiceProvider = Provider<VideoEditorService>((ref) {
  return EasyVideoEditorService();
});

/// One instance per creation-flow session (autoDispose so a stale
/// StreamController/active FFmpeg session doesn't outlive the screen that
/// created it).
final AutoDisposeProvider<VideoExportService> videoExportServiceProvider =
    Provider.autoDispose<VideoExportService>((ref) {
  final FfmpegVideoExportService service = FfmpegVideoExportService();
  ref.onDispose(() => unawaited(service.cancel()));
  return service;
});

final Provider<LocalVideoProber> localVideoProberProvider = Provider<LocalVideoProber>((ref) {
  return VideoPlayerLocalProber();
});

final Provider<VideoThumbnailService> videoThumbnailServiceProvider = Provider<VideoThumbnailService>((ref) {
  return FfmpegVideoThumbnailService();
});
