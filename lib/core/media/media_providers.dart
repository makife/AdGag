import "package:flutter_riverpod/flutter_riverpod.dart";

import "easy_video_editor_service.dart";
import "local_video_prober.dart";
import "video_editor_service.dart";
import "video_player_local_prober.dart";

final Provider<VideoEditorService> videoEditorServiceProvider = Provider<VideoEditorService>((ref) {
  return EasyVideoEditorService();
});

final Provider<LocalVideoProber> localVideoProberProvider = Provider<LocalVideoProber>((ref) {
  return VideoPlayerLocalProber();
});
