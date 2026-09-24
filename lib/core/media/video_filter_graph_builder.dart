import "../../features/create_ad/domain/video_project.dart";
import "video_editor_service.dart" show AppFlipDirection, AppVideoRotation;

/// Builds an FFmpeg `-filter_complex` argument list from a [VideoProject].
/// Pure Dart, no FFmpeg dependency of its own — [VideoExportService] is the
/// only thing that actually invokes FFmpegKit with this output, which keeps
/// "what the timeline means" (this file) separate from "how it gets
/// executed" (the export service), each independently testable.
///
/// Speed zones are implemented the way any NLE does variable-speed
/// playback: split video+audio into segments at every zone boundary,
/// `setpts` each video segment by `1/factor`, `atempo` each audio segment
/// by `factor`, then `concat` the segments back together — a single
/// `setpts` on the whole clip can't produce *only part* of it running at a
/// different speed.
abstract final class VideoFilterGraphBuilder {
  /// Returns the full FFmpeg argument list (everything after `ffmpeg`),
  /// including `-i` inputs, `-filter_complex`, stream mapping, codec
  /// selection, and the output path.
  static List<String> build({
    required VideoProject project,
    required String outputPath,
    required String videoEncoder, // e.g. "h264_mediacodec" / "h264_videotoolbox"
    required Map<TextFontFamily, String> fontFilePaths, // real filesystem paths — see fontfile= below
  }) {
    final List<String> inputs = <String>["-ss", _seconds(project.trimStart), "-i", project.videoPath];
    final List<String> extraInputArgs = <String>[];
    int nextInputIndex = 1;
    int? bgAudioInputIndex;
    final Map<String, int> imageOverlayInputIndex = <String, int>{};

    if (project.bgAudio != null) {
      extraInputArgs.addAll(<String>["-i", project.bgAudio!.filePath]);
      bgAudioInputIndex = nextInputIndex++;
    }
    for (final VideoOverlay overlay in project.overlays) {
      if (overlay is ImageOverlay) {
        extraInputArgs.addAll(<String>["-i", overlay.assetPath]);
        imageOverlayInputIndex[overlay.id] = nextInputIndex++;
      }
    }

    final String filterComplex = _buildFilterComplex(
      project: project,
      bgAudioInputIndex: bgAudioInputIndex,
      imageOverlayInputIndex: imageOverlayInputIndex,
      fontFilePaths: fontFilePaths,
    );

    return <String>[
      ...inputs,
      ...extraInputArgs,
      "-filter_complex", filterComplex,
      "-map", "[vout]",
      if (!project.removeAudio) ...<String>["-map", "[aout]"] else "-an",
      "-c:v", videoEncoder,
      // Mobile hardware encoders (mediacodec/videotoolbox) don't pick a
      // sensible default bitrate on their own — without an explicit
      // target the output is visibly low-quality regardless of source
      // resolution. 16M/20M targets a real 1080p master worth handing
      // to Mux (which re-transcodes for delivery — the local export
      // shouldn't already be the lossy step), not just "better than
      // before"; -maxrate/-bufsize bound the encoder's own rate-control
      // instead of leaving it to decide how strictly to honor -b:v.
      "-b:v", "16M",
      "-maxrate", "20M",
      "-bufsize", "20M",
      if (!project.removeAudio) ...<String>["-c:a", "aac"],
      "-t", _seconds(project.trimmedDuration),
      "-y",
      outputPath,
    ];
  }

  static String _buildFilterComplex({
    required VideoProject project,
    required int? bgAudioInputIndex,
    required Map<String, int> imageOverlayInputIndex,
    required Map<TextFontFamily, String> fontFilePaths,
  }) {
    final List<String> parts = <String>[];
    final _Timeline timeline = _Timeline.fromZones(project.speedZones, project.trimmedDuration);

    final List<String> videoLabels = <String>[];
    final List<String> audioLabels = <String>[];
    for (int i = 0; i < timeline.segments.length; i++) {
      final _Segment seg = timeline.segments[i];
      final String vLabel = "v$i";
      parts.add(
        "[0:v]trim=start=${_seconds(seg.start)}:end=${_seconds(seg.end)},"
        "setpts=(PTS-STARTPTS)/${seg.factor}[$vLabel]",
      );
      videoLabels.add("[$vLabel]");

      if (!project.removeAudio) {
        final String aLabel = "a$i";
        if (seg.factor == 1.0) {
          parts.add("[0:a]atrim=start=${_seconds(seg.start)}:end=${_seconds(seg.end)},asetpts=PTS-STARTPTS[$aLabel]");
        } else {
          parts.add(
            "[0:a]atrim=start=${_seconds(seg.start)}:end=${_seconds(seg.end)},asetpts=PTS-STARTPTS,"
            "atempo=${seg.factor}[$aLabel]",
          );
        }
        audioLabels.add("[$aLabel]");
      }
    }

    final String vConcatOut = timeline.segments.length > 1 ? "vconcat" : "v0";
    final String aConcatOut = timeline.segments.length > 1 ? "aconcat" : "a0";
    if (timeline.segments.length > 1) {
      parts.add("${videoLabels.join()}concat=n=${videoLabels.length}:v=1:a=0[vconcat]");
      if (!project.removeAudio) {
        parts.add("${audioLabels.join()}concat=n=${audioLabels.length}:v=0:a=1[aconcat]");
      }
    }

    String currentVideoLabel = vConcatOut;
    for (final VideoOverlay overlay in project.overlays) {
      final String nextLabel = "ov${parts.length}";
      final String enable = "between(t\\,${_seconds(overlay.startSec)}\\,${_seconds(overlay.endSec)})";
      switch (overlay) {
        case TextOverlay():
          final String escaped = _escapeDrawtext(overlay.text);
          final String colorHex = _argbToFFmpegHex(overlay.argbColor);
          final String fontFilePath = fontFilePaths[overlay.fontFamily] ?? fontFilePaths.values.first;
          final String escapedFontPath = _escapeDrawtext(fontFilePath);
          final String targetX = "(w*${overlay.xPercent})";
          final String xValue = switch (overlay.animation) {
            TextAnimation.none => targetX,
            TextAnimation.slideIn => "'${_slideInXExpr(overlay.startSec, targetX)}'",
            TextAnimation.popIn => targetX,
          };
          final String fontsizeValue = switch (overlay.animation) {
            TextAnimation.popIn => "'${_popInFontsizeExpr(overlay.startSec, overlay.fontSize.round())}'",
            TextAnimation.none || TextAnimation.slideIn => "${overlay.fontSize.round()}",
          };
          // Long-established, well-documented drawtext options (unlike
          // the animation x/fontsize expressions above, which are a
          // genuine unverified-on-device gamble) — low risk for real
          // legibility value, per CLAUDE.md's own spec calling
          // outline/shadow/background/opacity "extremely important" for
          // this app's text-heavy ad format.
          final List<String> extraOptions = <String>[
            if (overlay.opacity < 1.0) "alpha=${overlay.opacity.toStringAsFixed(2)}",
            if (overlay.hasOutline) ...<String>["bordercolor=black@0.8", "borderw=2"],
            if (overlay.hasShadow) ...<String>["shadowcolor=black@0.6", "shadowx=2", "shadowy=2"],
            if (overlay.hasBackground) ...<String>["box=1", "boxcolor=black@0.45", "boxborderw=6"],
          ];
          final String extra = extraOptions.isEmpty ? "" : ":${extraOptions.join(':')}";
          parts.add(
            "[$currentVideoLabel]drawtext=fontfile='$escapedFontPath':text='$escaped':fontcolor=$colorHex:"
            "fontsize=$fontsizeValue:"
            "x=$xValue:y=(h*${overlay.yPercent}):enable='$enable'$extra[$nextLabel]",
          );
        case ImageOverlay():
          final int inputIdx = imageOverlayInputIndex[overlay.id]!;
          final String scaled = "ovscale${parts.length}";
          parts.add("[$inputIdx:v]scale=iw*${overlay.widthPercent}/1:-1[$scaled]");
          final String composited;
          if (overlay.rotationDegrees == 0) {
            composited = scaled;
          } else {
            final String rotated = "ovrot${parts.length}";
            final String radians = (overlay.rotationDegrees * 3.141592653589793 / 180).toStringAsFixed(6);
            // c=none keeps the corners transparent instead of filling them
            // with black — required for a sticker to still look like a
            // rotated sticker, not a rotated black square with a sticker
            // inside it.
            parts.add(
              "[$scaled]rotate=$radians:c=none:ow=rotw($radians):oh=roth($radians)[$rotated]",
            );
            composited = rotated;
          }
          parts.add(
            "[$currentVideoLabel][$composited]overlay="
            "x=(main_w*${overlay.xPercent}):y=(main_h*${overlay.yPercent}):enable='$enable'[$nextLabel]",
          );
      }
      currentVideoLabel = nextLabel;
    }

    final List<String> transformFilters = <String>[];
    switch (project.rotation) {
      case AppVideoRotation.none:
        break;
      case AppVideoRotation.degrees90:
        transformFilters.add("transpose=1");
      case AppVideoRotation.degrees180:
        transformFilters.addAll(<String>["hflip", "vflip"]);
      case AppVideoRotation.degrees270:
        transformFilters.add("transpose=2");
    }
    switch (project.flip) {
      case AppFlipDirection.none:
        break;
      case AppFlipDirection.horizontal:
        transformFilters.add("hflip");
      case AppFlipDirection.vertical:
        transformFilters.add("vflip");
    }
    switch (project.colorFilter) {
      case AppColorFilter.none:
        break;
      case AppColorFilter.warm:
        transformFilters.add("eq=gamma_r=1.15:gamma_b=0.9:saturation=1.1");
      case AppColorFilter.cool:
        transformFilters.add("eq=gamma_r=0.9:gamma_b=1.15:saturation=1.05");
      case AppColorFilter.blackAndWhite:
        transformFilters.add("hue=s=0");
      case AppColorFilter.vintage:
        // Faded contrast + a warm cast + light grain-adjacent desaturation
        // — the "old film" look without a separate grain/noise filter,
        // which would add real per-frame render cost for a subtle effect.
        transformFilters.add("eq=contrast=0.85:saturation=0.75:gamma_r=1.1:brightness=0.02");
      case AppColorFilter.vivid:
        transformFilters.add("eq=saturation=1.45:contrast=1.15");
      case AppColorFilter.dramatic:
        transformFilters.add("eq=contrast=1.3:brightness=-0.04:saturation=0.9");
    }
    // Always the last video filter, not just when there's a rotation/
    // flip/color transform to chain it onto: drawtext and overlay (used
    // for text/sticker layers) can leave the frame in an alpha-carrying
    // pixel format (e.g. yuva420p) once composited, and H.264 hardware
    // encoders (h264_mediacodec on Android, h264_videotoolbox on iOS)
    // have no alpha channel support — feeding one an alpha format is a
    // real, reproducible cause of "export fails only when I add text or
    // a sticker, works fine on a plain trim." Explicitly normalizing to
    // yuv420p here is the standard fix, not a workaround.
    final List<String> finalVideoFilters = <String>[...transformFilters, "format=yuv420p"];
    parts.add("[$currentVideoLabel]${finalVideoFilters.join(',')}[vout]");

    if (!project.removeAudio) {
      String currentAudioLabel = aConcatOut;
      if (bgAudioInputIndex != null) {
        final BackgroundAudio bg = project.bgAudio!;
        final Duration musicDuration = bg.duration ?? (project.trimmedDuration - bg.startSec);
        // Trim the music file to its own window first — fades below are
        // relative to *this* trimmed clip's start, not the source file's.
        final List<String> fadeFilters = <String>[
          "atrim=duration=${_seconds(musicDuration.isNegative ? Duration.zero : musicDuration)}",
          "asetpts=PTS-STARTPTS",
        ];
        if (bg.fadeInDuration > Duration.zero) {
          fadeFilters.add("afade=t=in:st=0:d=${_seconds(bg.fadeInDuration)}");
        }
        if (bg.fadeOutDuration > Duration.zero) {
          final Duration fadeOutStart = musicDuration - bg.fadeOutDuration;
          fadeFilters.add(
            "afade=t=out:st=${_seconds(fadeOutStart < Duration.zero ? Duration.zero : fadeOutStart)}:"
            "d=${_seconds(bg.fadeOutDuration)}",
          );
        }
        fadeFilters.add("volume=${bg.volume}");
        if (bg.startSec > Duration.zero) {
          // Shifts the (already-trimmed) music so it starts at bg.startSec
          // on the main timeline instead of at t=0 — `all=1` applies the
          // delay to every audio channel.
          fadeFilters.add("adelay=${bg.startSec.inMilliseconds}:all=1");
        }
        parts.add("[$bgAudioInputIndex:a]${fadeFilters.join(',')}[bgfaded]");
        // duration=first: the mixed output is clamped to the main track's
        // length regardless of how long the (now delayed+trimmed) music
        // branch is, so a music window that runs past the clip's end
        // doesn't extend the export.
        parts.add("[$currentAudioLabel][bgfaded]amix=inputs=2:duration=first:dropout_transition=0[aout]");
        currentAudioLabel = "aout";
      } else {
        parts.add("[$currentAudioLabel]anull[aout]");
      }
    }

    return parts.join(";");
  }

  static String _seconds(Duration d) => (d.inMilliseconds / 1000.0).toStringAsFixed(3);

  static const double _animDuration = 0.35;

  /// Slides in from the right edge of the frame to [targetXExpr] over
  /// [_animDuration] seconds starting at [start]. `t` is drawtext's own
  /// per-frame timestamp — already relied on by the existing
  /// `enable='between(t,start,end)'` clause, so this uses the same
  /// timebase that's already proven to line up with [start]/[end]. Commas
  /// inside the expression are backslash-escaped because commas are
  /// otherwise a filtergraph-level separator, even inside a quoted
  /// option value — the documented FFmpeg idiom for a timed drawtext
  /// x/y expression.
  static String _slideInXExpr(Duration start, String targetXExpr) {
    final String s = _seconds(start);
    final double animEnd = start.inMilliseconds / 1000.0 + _animDuration;
    return "if(lt(t\\,${animEnd.toStringAsFixed(3)})\\,"
        "w-(w-$targetXExpr)*((t-$s)/$_animDuration)\\,"
        "$targetXExpr)";
  }

  /// Grows from 40% of [baseSize] up to full size over a shorter
  /// (0.25s) ramp — a "pop in" rather than a slide.
  static String _popInFontsizeExpr(Duration start, int baseSize) {
    final String s = _seconds(start);
    const double popDuration = 0.25;
    final double animEnd = start.inMilliseconds / 1000.0 + popDuration;
    return "if(lt(t\\,${animEnd.toStringAsFixed(3)})\\,"
        "$baseSize*(0.4+0.6*((t-$s)/$popDuration))\\,"
        "$baseSize)";
  }

  /// FFmpeg filtergraph escaping (distinct from shell escaping, which
  /// executeWithArgumentsAsync's arg-list form already avoids): backslash
  /// and the characters that are otherwise significant inside a
  /// single-quoted filter option value.
  static String _escapeDrawtext(String text) {
    // Order matters: escape backslashes first, so the backslashes this
    // function itself inserts below (for the quote and colon cases)
    // don't get double-escaped by a later step.
    return text
        .replaceAll(r"\", r"\\")
        .replaceAll(":", r"\:")
        .replaceAll("%", r"\%")
        // FFmpeg's own recommended way to embed a literal single quote
        // inside a single-quoted filter option value: close the quote,
        // an escaped quote, reopen the quote.
        .replaceAll("'", r"'\''");
  }

  static String _argbToFFmpegHex(int argbColor) {
    final String rgb = (argbColor & 0xFFFFFF).toRadixString(16).padLeft(6, "0");
    return "0x$rgb";
  }
}

final class _Segment {
  const _Segment({required this.start, required this.end, required this.factor});
  final Duration start;
  final Duration end;
  final double factor;
}

final class _Timeline {
  const _Timeline(this.segments);

  final List<_Segment> segments;

  factory _Timeline.fromZones(List<SpeedZone> zones, Duration totalDuration) {
    final List<SpeedZone> sorted = List<SpeedZone>.of(zones)
      ..sort((SpeedZone a, SpeedZone b) => a.start.compareTo(b.start));

    final List<_Segment> segments = <_Segment>[];
    Duration cursor = Duration.zero;
    for (final SpeedZone zone in sorted) {
      if (zone.start > cursor) {
        segments.add(_Segment(start: cursor, end: zone.start, factor: 1.0));
      }
      segments.add(_Segment(start: zone.start, end: zone.end, factor: zone.factor));
      cursor = zone.end;
    }
    if (cursor < totalDuration) {
      segments.add(_Segment(start: cursor, end: totalDuration, factor: 1.0));
    }
    if (segments.isEmpty) {
      segments.add(_Segment(start: Duration.zero, end: totalDuration, factor: 1.0));
    }
    return _Timeline(segments);
  }
}
