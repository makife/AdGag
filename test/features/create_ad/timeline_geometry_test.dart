import "package:flutter_test/flutter_test.dart";

import "package:adgag/features/create_ad/presentation/widgets/timeline_geometry.dart";

/// Left-anchoring invariant, per direct user feedback replacing the
/// earlier centered-playhead model (previously tested here against
/// "Bug 5"'s real-device report). Tests that time T, once scrolled to
/// [TimelineGeometry.scrollOffsetForTime], always sits exactly under the
/// fixed-position playhead ([TimelineGeometry.playheadOffset] from the
/// left) — not just re-reading the widget code, an actual proof the math
/// holds, across the same 0%/25%/50%/75%/100%-of-duration values and
/// several viewport widths as the model this replaced.
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

  group("left-anchored playhead invariant at 0%/25%/50%/75%/100% of a 10s clip", () {
    // Deliberately independent of viewportWidth — the whole point of the
    // left-anchored model (vs. the centered one it replaced) is that the
    // playhead's own screen position no longer depends on it.
    for (final double fraction in <double>[0.0, 0.25, 0.5, 0.75, 1.0]) {
      final double seconds = duration * fraction;
      test(
        "${(fraction * 100).round()}% (t=${seconds}s) sits exactly under the playhead",
        () {
          final double offset = TimelineGeometry.scrollOffsetForTime(seconds, pps);
          final double screenX = TimelineGeometry.screenPositionOfTime(
            seconds,
            pixelsPerSecond: pps,
            scrollOffset: offset,
          );
          expect(screenX, closeTo(TimelineGeometry.playheadOffset, 1e-9));
        },
      );
    }
  });

  test("t=0 sits exactly at the playhead, not offset to its right", () {
    // The original bug this class was extracted to prove correct: t=0
    // must land exactly under the playhead the instant the timeline
    // loads (scroll offset 0), not somewhere to its right.
    final double offset = TimelineGeometry.scrollOffsetForTime(0, pps);
    expect(offset, 0.0);
    final double screenX = TimelineGeometry.screenPositionOfTime(0, pixelsPerSecond: pps, scrollOffset: offset);
    expect(screenX, equals(TimelineGeometry.playheadOffset));
  });
}
