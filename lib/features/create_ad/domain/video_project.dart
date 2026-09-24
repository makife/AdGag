import "../../../core/media/video_editor_service.dart" show AppFlipDirection, AppVideoRotation;

/// Whole-clip color grading (CLAUDE.md section 35's "premium, playful"
/// look, applied at the user's choice, not by default). Each maps to one
/// FFmpeg `eq`/`hue` filter — see [VideoFilterGraphBuilder] — and one
/// `ColorFilter.matrix` approximation for the live preview, so what's
/// previewed while editing matches what actually gets rendered.
enum AppColorFilter { none, warm, cool, blackAndWhite, vintage, vivid, dramatic }

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
    this.startSec = Duration.zero,
    this.duration,
  });

  final String filePath;

  /// 0.0 (silent) to 1.0 (full volume, unscaled relative to the source file).
  final double volume;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;

  /// Where on the *trimmed clip's* timeline this music starts (not an
  /// offset into the music file itself) — draggable on [_Timeline]'s
  /// music lane the same way a [SpeedZone] is, so a track doesn't have
  /// to play across the whole clip.
  final Duration startSec;

  /// Null = plays from [startSec] through the end of the trimmed clip.
  final Duration? duration;
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

/// How a [TextOverlay] enters when it first becomes visible at
/// [VideoOverlay.startSec] — a fixed ~0.35s ramp implemented as an
/// FFmpeg `drawtext` position/size expression in
/// [VideoFilterGraphBuilder], not a separate render pass, so it doesn't
/// add any new export risk beyond drawtext itself (already the one
/// filter this app had to actually debug against a real font crash).
enum TextAnimation { none, slideIn, popIn }

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
    this.animation = TextAnimation.none,
    this.opacity = 1.0,
    this.hasOutline = false,
    this.hasShadow = false,
    this.hasBackground = false,
  });

  final String text;

  /// 0xAARRGGBB — a plain int rather than `dart:ui`'s `Color` so this
  /// domain model doesn't depend on the UI layer (CLAUDE.md section 21:
  /// "separate presentation, domain, and data").
  final int argbColor;
  final double fontSize;
  final TextAnimation animation;

  /// 0.0 (invisible) to 1.0 (fully opaque).
  final double opacity;

  /// A black stroke around each glyph (drawtext's `bordercolor`/`borderw`)
  /// — improves legibility over busy video without needing a background
  /// box, the more common social-app treatment for short captions.
  final bool hasOutline;

  /// A soft black drop shadow (drawtext's `shadowcolor`/`shadowx`/`shadowy`).
  final bool hasShadow;

  /// A semi-transparent black box behind the text (drawtext's
  /// `box`/`boxcolor`/`boxborderw`) — the alternative legibility
  /// treatment to an outline, for when the text needs to read over any
  /// background rather than just a busy one.
  final bool hasBackground;
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
    this.rotationDegrees = 0,
  });

  final String assetPath;

  /// Width as a percentage of frame width; height follows the source
  /// image's own aspect ratio (not independently settable — avoids
  /// letting a sticker get stretched out of proportion).
  final double widthPercent;

  /// Clockwise degrees. Rotating *text* isn't supported the same way —
  /// FFmpeg's `drawtext` filter has no rotate parameter, only image
  /// overlays can be rotated by [VideoFilterGraphBuilder]'s `rotate`
  /// filter without a much larger render-text-to-image detour.
  final double rotationDegrees;
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
    this.rotation = AppVideoRotation.none,
    this.flip = AppFlipDirection.none,
    this.removeAudio = false,
    this.colorFilter = AppColorFilter.none,
  });

  final String videoPath;
  final Duration trimStart;
  final Duration trimEnd;
  final List<SpeedZone> speedZones;
  final BackgroundAudio? bgAudio;
  final List<VideoOverlay> overlays;

  /// Applied to the whole clip, after trim/speed-zones/overlays are
  /// composited — the same simple whole-clip transforms the fast editor
  /// (`VideoEditorService`/`easy_video_editor`) offers, folded into this
  /// pipeline's single render pass whenever a zone or overlay also needs
  /// FFmpeg, so a user never has to choose between "the tool with
  /// rotate" and "the tool with slow-motion" — one editor, one export.
  final AppVideoRotation rotation;
  final AppFlipDirection flip;
  final bool removeAudio;
  final AppColorFilter colorFilter;

  Duration get trimmedDuration => trimEnd - trimStart;

  bool get hasAnyEdit =>
      trimStart > Duration.zero ||
      speedZones.isNotEmpty ||
      bgAudio != null ||
      overlays.isNotEmpty ||
      rotation != AppVideoRotation.none ||
      flip != AppFlipDirection.none ||
      removeAudio ||
      colorFilter != AppColorFilter.none;

  VideoProject withTrim({required Duration start, required Duration end}) => _copyWith(
        trimStart: start,
        trimEnd: end,
      );

  VideoProject withRotation(AppVideoRotation value) => _copyWith(rotation: value);

  VideoProject withFlip(AppFlipDirection value) => _copyWith(flip: value);

  VideoProject withRemoveAudio({required bool value}) => _copyWith(removeAudio: value);

  VideoProject withColorFilter(AppColorFilter value) => _copyWith(colorFilter: value);

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

  /// Replaces [oldZone] with [updated] in place, without the overlap
  /// check [withSpeedZone] applies — used for dragging an existing
  /// zone's own edge, where "does this still fit next to its siblings"
  /// is deliberately left unenforced (see [_Timeline]'s own doc comment:
  /// resize collision-avoidance against other zones is out of scope).
  /// A no-op if [oldZone] isn't found.
  VideoProject replaceSpeedZone(SpeedZone oldZone, SpeedZone updated) {
    final int index = speedZones.indexOf(oldZone);
    if (index == -1) {
      return this;
    }
    final List<SpeedZone> next = List<SpeedZone>.of(speedZones);
    next[index] = updated;
    return _copyWith(speedZones: next);
  }

  VideoProject withBgAudio(BackgroundAudio? audio) => _copyWith(bgAudio: audio, clearBgAudio: audio == null);

  VideoProject withOverlay(VideoOverlay overlay) {
    return _copyWith(overlays: <VideoOverlay>[...overlays, overlay]);
  }

  VideoProject withoutOverlay(String overlayId) {
    return _copyWith(overlays: overlays.where((VideoOverlay o) => o.id != overlayId).toList(growable: false));
  }

  /// Replaces the overlay with [updated]'s `id` in place — used for
  /// drag/pinch/rotate and timeline edge-resize, both of which mutate an
  /// *existing* overlay rather than adding a new one. A no-op if no
  /// overlay with that id exists.
  VideoProject updateOverlay(VideoOverlay updated) {
    final int index = overlays.indexWhere((VideoOverlay o) => o.id == updated.id);
    if (index == -1) {
      return this;
    }
    final List<VideoOverlay> next = List<VideoOverlay>.of(overlays);
    next[index] = updated;
    return _copyWith(overlays: next);
  }

  VideoProject _copyWith({
    Duration? trimStart,
    Duration? trimEnd,
    List<SpeedZone>? speedZones,
    BackgroundAudio? bgAudio,
    bool clearBgAudio = false,
    List<VideoOverlay>? overlays,
    AppVideoRotation? rotation,
    AppFlipDirection? flip,
    bool? removeAudio,
    AppColorFilter? colorFilter,
  }) {
    return VideoProject(
      videoPath: videoPath,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
      speedZones: speedZones ?? this.speedZones,
      bgAudio: clearBgAudio ? null : (bgAudio ?? this.bgAudio),
      overlays: overlays ?? this.overlays,
      rotation: rotation ?? this.rotation,
      flip: flip ?? this.flip,
      removeAudio: removeAudio ?? this.removeAudio,
      colorFilter: colorFilter ?? this.colorFilter,
    );
  }
}
