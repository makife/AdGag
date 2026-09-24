import "package:flutter_test/flutter_test.dart";

import "package:adgag/core/media/video_filter_graph_builder.dart";
import "package:adgag/features/create_ad/domain/video_project.dart";

/// Export-combination coverage per the tightened video-editor spec's
/// section 7 ("Create explicit export test cases... A-M"). What this
/// *can* verify in a pure-Dart unit test, with no FFmpeg binary or real
/// video file available in this environment: that [VideoFilterGraphBuilder]
/// produces a well-formed `-filter_complex` graph (every referenced
/// stream label was actually defined earlier, or is a raw input like
/// `0:v`) for each combination, that pixel-format normalization
/// (`format=yuv420p`) is present in every case — the actual fix for the
/// "export fails only when text/sticker/filter are combined" bug this
/// round diagnosed — and that the right filters appear for the right
/// features. It cannot verify the command actually runs, the output
/// plays back, or matches the preview frame-for-frame; that needs a real
/// device (see this round's CLAUDE.md entry).
void main() {
  const String video = "/tmp/source.mp4";
  const String font = "/tmp/font.ttf";
  const String encoder = "h264_mediacodec";

  /// Validates that every `[label]` consumed by a filter was defined by
  /// an earlier filter's output (or is a raw demuxer reference like
  /// `0:v`/`1:a`) — the structural bug class most likely to silently
  /// break FFmpeg ("Stream specifier ... not found" / "No such filter
  /// input/output"), and the one class of error a unit test can
  /// actually catch without running FFmpeg itself.
  void expectWellFormedGraph(String filterComplex) {
    final Set<String> defined = <String>{};
    final RegExp labelPattern = RegExp(r"\[([^\]]+)\]");
    for (final String segment in filterComplex.split(";")) {
      final List<String> labels = labelPattern.allMatches(segment).map((Match m) => m.group(1)!).toList();
      // Everything up to the filter name (first char that isn't part of
      // a leading [label] group) are inputs; the graph as this app
      // builds it always ends a segment with its own output label(s),
      // so the *last* label in the segment is the output, the rest
      // (excluding raw N:v/N:a demuxer refs) must already be defined.
      expect(labels, isNotEmpty, reason: "segment has no labels at all: $segment");
      final String output = labels.last;
      for (final String label in labels.sublist(0, labels.length - 1)) {
        final bool isRawInput = RegExp(r"^\d+:[va]$").hasMatch(label);
        if (!isRawInput) {
          expect(
            defined.contains(label),
            isTrue,
            reason: "filter references undefined label [$label] in segment: $segment",
          );
        }
      }
      defined.add(output);
    }
    expect(defined.contains("vout"), isTrue, reason: "graph never defines [vout]");
  }

  List<String> buildArgs(VideoProject project) => VideoFilterGraphBuilder.build(
        project: project,
        outputPath: "/tmp/out.mp4",
        videoEncoder: encoder,
        fontFilePaths: <TextFontFamily, String>{for (final TextFontFamily f in TextFontFamily.values) f: font},
      );

  String filterComplexOf(List<String> args) {
    final int i = args.indexOf("-filter_complex");
    expect(i, greaterThanOrEqualTo(0), reason: "no -filter_complex in args: $args");
    return args[i + 1];
  }

  VideoProject baseProject({
    Duration trimStart = Duration.zero,
    Duration trimEnd = const Duration(seconds: 8),
    List<SpeedZone> speedZones = const <SpeedZone>[],
    List<VideoOverlay> overlays = const <VideoOverlay>[],
    AppColorFilter colorFilter = AppColorFilter.none,
    bool removeAudio = false,
    BackgroundAudio? bgAudio,
  }) =>
      VideoProject(
        videoPath: video,
        trimStart: trimStart,
        trimEnd: trimEnd,
        speedZones: speedZones,
        overlays: overlays,
        colorFilter: colorFilter,
        removeAudio: removeAudio,
        bgAudio: bgAudio,
      );

  const TextOverlay textOverlay = TextOverlay(
    id: "t1",
    xPercent: 0.1,
    yPercent: 0.1,
    startSec: Duration(seconds: 1),
    duration: Duration(seconds: 3),
    text: "ROCK™",
  );

  const ImageOverlay stickerOverlay = ImageOverlay(
    id: "s1",
    xPercent: 0.3,
    yPercent: 0.3,
    startSec: Duration(seconds: 2),
    duration: Duration(seconds: 2),
    assetPath: "/tmp/sticker.png",
  );

  final SpeedZone slowZone = const SpeedZone(start: Duration(seconds: 2), end: Duration(seconds: 4), factor: 0.5);
  final SpeedZone fastZone = const SpeedZone(start: Duration(seconds: 2), end: Duration(seconds: 4), factor: 2.0);

  test("B: trim only produces a well-formed graph with format=yuv420p", () {
    final List<String> args = buildArgs(baseProject());
    final String fc = filterComplexOf(args);
    expectWellFormedGraph(fc);
    expect(fc, contains("format=yuv420p"));
    expect(args, containsAllInOrder(<String>["-map", "[vout]"]));
  });

  test("C: text only renders via drawtext and stays well-formed", () {
    final List<String> args = buildArgs(baseProject(overlays: const <VideoOverlay>[textOverlay]));
    final String fc = filterComplexOf(args);
    expectWellFormedGraph(fc);
    expect(fc, contains("drawtext="));
    expect(fc, contains("format=yuv420p"));
  });

  test("D: sticker only renders via overlay= and stays well-formed", () {
    final List<String> args = buildArgs(baseProject(overlays: const <VideoOverlay>[stickerOverlay]));
    final String fc = filterComplexOf(args);
    expectWellFormedGraph(fc);
    expect(fc, contains("overlay="));
    expect(fc, contains("format=yuv420p"));
  });

  test("E: filter only applies the right GPL-free expression (no eq=)", () {
    final List<String> args = buildArgs(baseProject(colorFilter: AppColorFilter.vivid));
    final String fc = filterComplexOf(args);
    expectWellFormedGraph(fc);
    expect(fc, contains("hue=s=1.45"));
    expect(fc, contains("curves=preset=increase_contrast"));
  });

  test(
    "no AppColorFilter ever emits the 'eq' filter — real-device confirmed "
    "GPL-only, absent from this LGPL FFmpeg build ('No such filter: eq')",
    () {
      for (final AppColorFilter filter in AppColorFilter.values) {
        final String fc = filterComplexOf(buildArgs(baseProject(colorFilter: filter)));
        // Matches "eq=" or "eq:" as a filter name, not e.g. a variable
        // named requeue — filter names are preceded by [labels] or a
        // comma/semicolon in this app's own generated graphs.
        expect(
          RegExp(r"(^|[,;\]])eq[=:]").hasMatch(fc),
          isFalse,
          reason: "$filter emitted the unavailable 'eq' filter: $fc",
        );
      }
    },
  );

  test("F: speed 0.5x (slow motion) uses atempo and setpts on the zone", () {
    final List<String> args = buildArgs(baseProject(speedZones: <SpeedZone>[slowZone]));
    final String fc = filterComplexOf(args);
    expectWellFormedGraph(fc);
    expect(fc, contains("/0.5"));
    expect(fc, contains("atempo=0.5"));
  });

  test("G: speed 2x uses atempo and setpts on the zone", () {
    final List<String> args = buildArgs(baseProject(speedZones: <SpeedZone>[fastZone]));
    final String fc = filterComplexOf(args);
    expectWellFormedGraph(fc);
    expect(fc, contains("/2.0"));
    expect(fc, contains("atempo=2.0"));
  });

  test("H: text + filter combined stays well-formed", () {
    final List<String> args = buildArgs(
      baseProject(overlays: const <VideoOverlay>[textOverlay], colorFilter: AppColorFilter.dramatic),
    );
    final String fc = filterComplexOf(args);
    expectWellFormedGraph(fc);
    expect(fc, contains("drawtext="));
    expect(fc, contains("curves=preset=strong_contrast"));
    expect(fc, contains("format=yuv420p"));
  });

  test("I: slow motion + text combined stays well-formed", () {
    final List<String> args = buildArgs(
      baseProject(speedZones: <SpeedZone>[slowZone], overlays: const <VideoOverlay>[textOverlay]),
    );
    final String fc = filterComplexOf(args);
    expectWellFormedGraph(fc);
    expect(fc, contains("drawtext="));
    expect(fc, contains("atempo=0.5"));
  });

  test("J: slow motion + text + filter combined stays well-formed", () {
    final List<String> args = buildArgs(
      baseProject(
        speedZones: <SpeedZone>[slowZone],
        overlays: const <VideoOverlay>[textOverlay],
        colorFilter: AppColorFilter.warm,
      ),
    );
    final String fc = filterComplexOf(args);
    expectWellFormedGraph(fc);
    expect(fc, contains("drawtext="));
    expect(fc, contains("atempo=0.5"));
    expect(fc, contains("colortemperature=temperature=4500"));
    expect(fc, contains("format=yuv420p"));
  });

  test(
    "K: trim + text + sticker + filter + speed all combined — the exact "
    "failure-report shape — stays well-formed with a single [vout]",
    () {
      final List<String> args = buildArgs(
        baseProject(
          trimStart: const Duration(seconds: 1),
          trimEnd: const Duration(seconds: 9),
          speedZones: <SpeedZone>[slowZone],
          overlays: const <VideoOverlay>[textOverlay, stickerOverlay],
          colorFilter: AppColorFilter.vintage,
        ),
      );
      final String fc = filterComplexOf(args);
      expectWellFormedGraph(fc);
      expect(fc, contains("drawtext="));
      expect(fc, contains("overlay="));
      expect(fc, contains("atempo=0.5"));
      expect(fc, contains("format=yuv420p"));
      // Exactly one [vout] definition — a duplicate would mean two
      // filters raced to write the final output label.
      expect("[vout]".allMatches(fc).length, 1);
    },
  );

  test("L: source with audio maps [aout] and encodes aac", () {
    final List<String> args = buildArgs(baseProject());
    expect(args, containsAllInOrder(<String>["-map", "[aout]"]));
    expect(args, containsAllInOrder(<String>["-c:a", "aac"]));
    expect(args.contains("-an"), isFalse);
  });

  test("M: removeAudio maps no audio stream and passes -an", () {
    final List<String> args = buildArgs(baseProject(removeAudio: true));
    expect(args.contains("-an"), isTrue);
    expect(args.contains("[aout]"), isFalse);
    expect(args.contains("-c:a"), isFalse);
  });

  test("hardware encoder and a high-quality bitrate target are always set", () {
    final List<String> args = buildArgs(baseProject());
    expect(args, containsAllInOrder(<String>["-c:v", encoder]));
    expect(args, contains("-b:v"));
  });

  test("background music combined with text/filter/speed stays well-formed", () {
    final List<String> args = buildArgs(
      baseProject(
        speedZones: <SpeedZone>[slowZone],
        overlays: const <VideoOverlay>[textOverlay],
        colorFilter: AppColorFilter.cool,
        bgAudio: const BackgroundAudio(filePath: "/tmp/music.mp3", volume: 0.5),
      ),
    );
    final String fc = filterComplexOf(args);
    expectWellFormedGraph(fc);
    expect(fc, contains("amix=inputs=2"));
  });
}
