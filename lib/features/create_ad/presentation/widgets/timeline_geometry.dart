/// Pure time↔pixel math for the editor timeline's centered-playhead,
/// horizontally-scrolling geometry (see `_Timeline`'s own doc comment in
/// trim_step.dart). Extracted into its own public, non-widget file so
/// it's independently unit-testable without a Flutter widget-test
/// harness — a real-device bug report questioned whether this geometry
/// was actually correct, and "read the widget's build method carefully"
/// isn't a substitute for a test that can be run and re-run.
///
/// The scrollable content is the clip (at [TimelineGeometry] pixels/
/// second) with exactly `viewportWidth / 2` of empty leading and
/// trailing padding, so that both the very first and very last instant
/// of the clip can be scrolled to the centered playhead — not just
/// whatever's in the middle. The one invariant that matters: for time
/// T, when the `ScrollController` offset equals [scrollOffsetForTime]
/// applied to T, T's own screen position is exactly `viewportWidth / 2`
/// — the same fixed position the playhead itself is drawn at, for any
/// viewport width. That invariant is proven algebraically in this
/// class's tests, not just asserted.
abstract final class TimelineGeometry {
  /// Where [seconds] sits along the *unpadded* scrollable content, in
  /// pixels — content's own coordinate space, not screen position and
  /// not accounting for the leading padding.
  static double timeToPixels(double seconds, double pixelsPerSecond) => seconds * pixelsPerSecond;

  static double pixelsToTime(double pixels, double pixelsPerSecond) => pixels / pixelsPerSecond;

  /// The `ScrollController` offset that puts [seconds] exactly under the
  /// centered playhead. Content position of `seconds` (including the
  /// leading `viewportWidth/2` padding) is `viewportWidth/2 +
  /// seconds*pixelsPerSecond`; that point's screen position at scroll
  /// offset S is `contentPosition - S`. Setting screen position equal to
  /// the playhead's own fixed position (`viewportWidth/2`) and solving
  /// for S: the `viewportWidth/2` terms cancel, leaving exactly
  /// `seconds * pixelsPerSecond` — independent of viewport width, which
  /// is why this function doesn't take one as a parameter.
  static double scrollOffsetForTime(double seconds, double pixelsPerSecond) => seconds * pixelsPerSecond;

  static double timeForScrollOffset(double scrollOffset, double pixelsPerSecond) => scrollOffset / pixelsPerSecond;

  /// The screen X position of `seconds` given the current scroll
  /// [scrollOffset] and [viewportWidth] — used only by tests to verify
  /// the centering invariant directly, not by the widget itself (which
  /// achieves centering structurally via the padding + a fixed-position
  /// playhead, not by computing this for every element).
  static double screenPositionOfTime(
    double seconds, {
    required double pixelsPerSecond,
    required double scrollOffset,
    required double viewportWidth,
  }) =>
      viewportWidth / 2 + timeToPixels(seconds, pixelsPerSecond) - scrollOffset;
}
