import "package:flutter_test/flutter_test.dart";

import "package:adgag/features/create_ad/presentation/widgets/timeline_geometry.dart";

/// Bug 5 (real-device report): "the fixed red playhead is around the
/// center, but at time 0 the video begins to its RIGHT, leaving a huge
/// empty area on the left." This directly tests the centering invariant
/// the bug report describes at 0%/25%/50%/75%/100% of a clip's duration,
/// across several viewport widths and pixels-per-second scales — not
/// just re-reading the widget code, an actual proof the math holds.
void main() {
  const double pps = 70;
  const double duration = 10;

  group("timeToPixels / pixelsToTime round-trip", () {
    for (final double sec in <double>[0, 2.5, 5, 7.5, 10]) {
      test("$sec seconds round-trips through pixels", () {
        final double px = TimelineGeometry.timeToPixels(sec, pps);
        expect(TimelineGeometry.pixelsToTime(px, pps), closeTo(sec, 1e-9));
      });
    }
  });

  group("scrollOffsetForTime / timeForScrollOffset round-trip", () {
    for (final double sec in <double>[0, 2.5, 5, 7.5, 10]) {
      test("$sec seconds round-trips through scroll offset", () {
        final double offset = TimelineGeometry.scrollOffsetForTime(sec, pps);
        expect(TimelineGeometry.timeForScrollOffset(offset, pps), closeTo(sec, 1e-9));
      });
    }
  });

  group("centering invariant at 0%/25%/50%/75%/100% of a 10s clip", () {
    for (final double viewportWidth in <double>[320, 400, 800]) {
      for (final double fraction in <double>[0.0, 0.25, 0.5, 0.75, 1.0]) {
        final double seconds = duration * fraction;
        test(
          "${(fraction * 100).round()}% (t=${seconds}s) sits exactly under "
          "the playhead at viewportWidth=$viewportWidth",
          () {
            final double offset = TimelineGeometry.scrollOffsetForTime(seconds, pps);
            final double screenX = TimelineGeometry.screenPositionOfTime(
              seconds,
              pixelsPerSecond: pps,
              scrollOffset: offset,
              viewportWidth: viewportWidth,
            );
            // The playhead itself is drawn at exactly viewportWidth/2 —
            // see _Timeline's build(). This is the bug report's own
            // stated requirement: "the first frame must align directly
            // underneath the center playhead," generalized to any T.
            expect(screenX, closeTo(viewportWidth / 2, 1e-9));
          },
        );
      }
    }
  });

  test("t=0 is not offset to the right of the playhead by construction", () {
    // The specific failure mode described: "at time 0 the video begins
    // to its RIGHT, leaving a huge empty area on the left" would mean
    // screenPositionOfTime(0, ...) > viewportWidth/2 when scrolled to
    // scrollOffsetForTime(0). It must be exactly equal, not greater.
    const double viewportWidth = 400;
    final double offset = TimelineGeometry.scrollOffsetForTime(0, pps);
    final double screenX = TimelineGeometry.screenPositionOfTime(
      0,
      pixelsPerSecond: pps,
      scrollOffset: offset,
      viewportWidth: viewportWidth,
    );
    expect(screenX, equals(viewportWidth / 2));
  });
}
