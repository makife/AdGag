import "package:flutter_riverpod/flutter_riverpod.dart";

import "easy_video_editor_trimmer.dart";
import "local_video_prober.dart";
import "video_player_local_prober.dart";
import "video_trimmer.dart";

final Provider<VideoTrimmer> videoTrimmerProvider = Provider<VideoTrimmer>((ref) {
  return EasyVideoEditorTrimmer();
});

final Provider<LocalVideoProber> localVideoProberProvider = Provider<LocalVideoProber>((ref) {
  return VideoPlayerLocalProber();
});
