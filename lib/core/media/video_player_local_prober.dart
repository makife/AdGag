import "dart:io";

import "package:video_player/video_player.dart";

import "local_video_prober.dart";

/// Uses `video_player` itself to read a local file's duration — avoids
/// depending on the trim package's metadata support (unverified in this
/// environment) for something video_player already does reliably.
final class VideoPlayerLocalProber implements LocalVideoProber {
  @override
  Future<Duration> probeDuration(String filePath) async {
    final VideoPlayerController controller = VideoPlayerController.file(File(filePath));
    try {
      await controller.initialize();
      return controller.value.duration;
    } finally {
      await controller.dispose();
    }
  }
}
