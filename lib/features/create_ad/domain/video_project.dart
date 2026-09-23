/// A time-ranged speed multiplier — e.g. 0.5 across seconds 3-5 for a
/// slow-motion window within an otherwise normal-speed clip. Multiple
/// zones may exist; zones must not overlap (enforced by
/// [VideoProject.withSpeedZone], not by this class itself, so a bare
/// [SpeedZone] stays a simple, unconditional value type).
final class SpeedZone {
  const SpeedZone({required this.start, required this.end, required this.factor});

  final Duration start;
  final Duration end;

  /// e.g. 0.5 = half speed (slow motion), 2.0 = double speed.
  final double factor;

  bool overlaps(SpeedZone other) => start < other.end && other.start < end;
}

/// Background music mixed under the clip's original audio (CLAUDE.md
/// section 4: "optional music/audio architecture").
final class BackgroundAudio {
  const BackgroundAudio({
    required this.filePath,
    this.volume = 1.0,
    this.fadeInDuration = Duration.zero,
    this.fadeOutDuration = Duration.zero,
  });

  final String filePath;

  /// 0.0 (silent) to 1.0 (full volume, unscaled relative to the source file).
  final double volume;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;
}

/// A single overlay element (text or image/sticker) shown from [startSec]
/// for [duration], positioned by percentage of frame width/height (not
/// pixels — resolution-independent, and what a drag-to-position preview
/// naturally produces).
sealed class VideoOverlay {
  const VideoOverlay({
    required this.id,
    required this.xPercent,
    required this.yPercent,
    required this.startSec,
    required this.duration,
  });

  /// Stable identity for editing/removing a specific overlay from the
  /// project (list order alone isn't stable once items can be
  /// added/removed out of order).
  final String id;

  /// 0.0-1.0, left/top-anchored.
  final double xPercent;
  final double yPercent;
  final Duration startSec;
  final Duration duration;

  Duration get endSec => startSec + duration;
}

final class TextOverlay extends VideoOverlay {
  const TextOverlay({
    required super.id,
    required super.xPercent,
    required super.yPercent,
    required super.startSec,
    required super.duration,
    required this.text,
    this.argbColor = 0xFFFFFFFF,
    this.fontSize = 32,
  });

  final String text;

  /// 0xAARRGGBB — a plain int rather than `dart:ui`'s `Color` so this
  /// domain model doesn't depend on the UI layer (CLAUDE.md section 21:
  /// "separate presentation, domain, and data").
  final int argbColor;
  final double fontSize;
}

/// A static image or a single sticker/GIF *frame* composited as an image
/// overlay (CLAUDE.md section 4/38 keeps the editor lightweight — full
/// animated-GIF-as-video overlay is a further step up in filter_complex
/// complexity; a static sticker image is the first cut of this feature).
final class ImageOverlay extends VideoOverlay {
  const ImageOverlay({
    required super.id,
    required super.xPercent,
    required super.yPercent,
    required super.startSec,
    required super.duration,
    required this.assetPath,
    this.widthPercent = 0.3,
  });

  final String assetPath;

  /// Width as a percentage of frame width; height follows the source
  /// image's own aspect ratio (not independently settable — avoids
  /// letting a sticker get stretched out of proportion).
  final double widthPercent;
}

/// The full editable state of one Ad's creation-flow editing session
/// (CLAUDE.md section 38's "trim/edit" step). Immutable — every edit
/// action produces a new [VideoProject] via one of the `with*` methods,
/// the same pattern as [CreateAdFlowState.copyWith].
final class VideoProject {
  const VideoProject({
    required this.videoPath,
    required this.trimStart,
    required this.trimEnd,
    this.speedZones = const <SpeedZone>[],
    this.bgAudio,
    this.overlays = const <VideoOverlay>[],
  });

  final String videoPath;
  final Duration trimStart;
  final Duration trimEnd;
  final List<SpeedZone> speedZones;
  final BackgroundAudio? bgAudio;
  final List<VideoOverlay> overlays;

  Duration get trimmedDuration => trimEnd - trimStart;

  bool get hasAnyEdit =>
      speedZones.isNotEmpty || bgAudio != null || overlays.isNotEmpty;

  VideoProject withTrim({required Duration start, required Duration end}) {
    return VideoProject(
      videoPath: videoPath,
      trimStart: start,
      trimEnd: end,
      speedZones: speedZones,
      bgAudio: bgAudio,
      overlays: overlays,
    );
  }

  /// Adds [zone], rejecting it if it overlaps an existing zone (two
  /// different speed factors can't both apply to the same instant).
  VideoProject withSpeedZone(SpeedZone zone) {
    if (speedZones.any((SpeedZone existing) => existing.overlaps(zone))) {
      throw ArgumentError("Speed zone overlaps an existing one");
    }
    return _copyWith(speedZones: <SpeedZone>[...speedZones, zone]);
  }

  VideoProject withoutSpeedZone(SpeedZone zone) {
    return _copyWith(speedZones: speedZones.where((SpeedZone z) => z != zone).toList(growable: false));
  }

  VideoProject withBgAudio(BackgroundAudio? audio) => _copyWith(bgAudio: audio, clearBgAudio: audio == null);

  VideoProject withOverlay(VideoOverlay overlay) {
    return _copyWith(overlays: <VideoOverlay>[...overlays, overlay]);
  }

  VideoProject withoutOverlay(String overlayId) {
    return _copyWith(overlays: overlays.where((VideoOverlay o) => o.id != overlayId).toList(growable: false));
  }

  VideoProject _copyWith({
    List<SpeedZone>? speedZones,
    BackgroundAudio? bgAudio,
    bool clearBgAudio = false,
    List<VideoOverlay>? overlays,
  }) {
    return VideoProject(
      videoPath: videoPath,
      trimStart: trimStart,
      trimEnd: trimEnd,
      speedZones: speedZones ?? this.speedZones,
      bgAudio: clearBgAudio ? null : (bgAudio ?? this.bgAudio),
      overlays: overlays ?? this.overlays,
    );
  }
}
