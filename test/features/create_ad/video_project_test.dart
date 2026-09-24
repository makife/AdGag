import "package:flutter_test/flutter_test.dart";

import "package:adgag/core/media/video_editor_service.dart";
import "package:adgag/features/create_ad/domain/video_project.dart";

VideoProject _base({
  List<SpeedZone> speedZones = const <SpeedZone>[],
  BackgroundAudio? bgAudio,
  List<VideoOverlay> overlays = const <VideoOverlay>[],
  AppVideoRotation rotation = AppVideoRotation.none,
  AppFlipDirection flip = AppFlipDirection.none,
  bool removeAudio = false,
  AppColorFilter colorFilter = AppColorFilter.none,
}) {
  return VideoProject(
    videoPath: "/tmp/clip.mp4",
    trimStart: Duration.zero,
    trimEnd: const Duration(seconds: 10),
    speedZones: speedZones,
    bgAudio: bgAudio,
    overlays: overlays,
    rotation: rotation,
    flip: flip,
    removeAudio: removeAudio,
    colorFilter: colorFilter,
  );
}

void main() {
  group("VideoProject.needsPlaybackCoordination (videoeditor8.txt section 9)", () {
    test("a default, unedited project needs none", () {
      expect(_base().needsPlaybackCoordination, isFalse);
    });

    test("a speed zone needs coordination", () {
      expect(
        _base(
          speedZones: const <SpeedZone>[
            SpeedZone(start: Duration(seconds: 1), end: Duration(seconds: 2), factor: 0.5),
          ],
        ).needsPlaybackCoordination,
        isTrue,
      );
    });

    test("background music needs coordination", () {
      expect(
        _base(bgAudio: const BackgroundAudio(filePath: "/tmp/music.mp3")).needsPlaybackCoordination,
        isTrue,
      );
    });

    // Overlays are evaluated independently by their own AnimatedBuilder
    // listeners (see trim_step.dart's preview Stack) — they don't need
    // _onTransportChanged to do anything on their behalf, so they must
    // NOT gate the fast path off.
    test("overlays alone do not need coordination", () {
      expect(
        _base(
          overlays: const <VideoOverlay>[
            TextOverlay(
              id: "t1",
              xPercent: 0.1,
              yPercent: 0.1,
              startSec: Duration(seconds: 1),
              duration: Duration(seconds: 2),
              text: "ROCK",
            ),
          ],
        ).needsPlaybackCoordination,
        isFalse,
      );
    });

    // Rotation/flip/filter/mute are one-shot widget-tree or apply-once
    // concerns, not per-tick ones — none of them should force the
    // per-tick speed/music coordination path to run either.
    test("rotation, flip, mute, and a color filter alone do not need coordination", () {
      expect(_base(rotation: AppVideoRotation.degrees90).needsPlaybackCoordination, isFalse);
      expect(_base(flip: AppFlipDirection.horizontal).needsPlaybackCoordination, isFalse);
      expect(_base(removeAudio: true).needsPlaybackCoordination, isFalse);
      expect(_base(colorFilter: AppColorFilter.warm).needsPlaybackCoordination, isFalse);
    });
  });
}
