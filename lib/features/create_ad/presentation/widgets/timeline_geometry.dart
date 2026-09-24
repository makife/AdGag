/// Pure time↔pixel math for the editor timeline's left-anchored,
/// horizontally-scrolling geometry (see `_Timeline`'s own doc comment in
/// trim_step.dart). Extracted into its own public, non-widget file so
/// it's independently unit-testable without a Flutter widget-test
/// harness — a real-device bug report questioned whether this geometry
/// was actually correct, and "read the widget's build method carefully"
/// isn't a substitute for a test that can be run and re-run.
///
/// Per direct user feedback, this replaced an earlier centered-playhead
/// model (playhead fixed at `viewportWidth/2`, equal leading/trailing
/// padding): the playhead now sits at a small FIXED offset
/// ([playheadOffset]) from the left edge, independent of viewport width,
/// so the timeline reads left-to-right starting from the left — the clip's
/// own first instant sits just past the left edge, not in the middle of
/// a wide empty margin.
///
/// The scrollable content has exactly [playheadOffset] of leading padding
/// (so t=0's own content position already equals [playheadOffset],
/// matching scroll offset 0) and `viewportWidth - playheadOffset` of
/// trailing padding (so the clip's very last instant can still reach the
/// playhead, not just whatever's left after it). The one invariant that
/// matters: for time T, when the `ScrollController` offset equals
/// [scrollOffsetForTime] applied to T, T's own screen position is exactly
/// [playheadOffset] — the same fixed position the playhead itself is
/// drawn at, for any viewport width. That invariant is proven
/// algebraically in this class's tests, not just asserted.
abstract final class TimelineGeometry {
  /// Fixed screen-space X offset (logical pixels) of the playhead from
  /// the left edge of the timeline viewport.
  static const double playheadOffset = 24.0;

  /// Where [seconds] sits along the *unpadded* scrollable content, in
  /// pixels — content's own coordinate space, not screen position and
  /// not accounting for the leading padding.
  static double timeToPixels(double seconds, double pixelsPerSecond) => seconds * pixelsPerSecond;

  static double pixelsToTime(double pixels, double pixelsPerSecond) => pixels / pixelsPerSecond;

  /// The `ScrollController` offset that puts [seconds] exactly under the
  /// playhead. Content position of `seconds` (including the leading
  /// [playheadOffset] padding) is `playheadOffset + seconds*pixelsPerSecond`;
  /// that point's screen position at scroll offset S is
  /// `contentPosition - S`. Setting screen position equal to the
  /// playhead's own fixed position ([playheadOffset]) and solving for S:
  /// the [playheadOffset] terms cancel, leaving exactly
  /// `seconds * pixelsPerSecond` — independent of viewport width, which
  /// is why this function doesn't take one as a parameter.
  static double scrollOffsetForTime(double seconds, double pixelsPerSecond) => seconds * pixelsPerSecond;

  static double timeForScrollOffset(double scrollOffset, double pixelsPerSecond) => scrollOffset / pixelsPerSecond;

  /// The screen X position of `seconds` given the current scroll
  /// [scrollOffset] — used only by tests to verify the left-anchoring
  /// invariant directly, not by the widget itself (which achieves it
  /// structurally via the padding + a fixed-position playhead, not by
  /// computing this for every element).
  static double screenPositionOfTime(
    double seconds, {
    required double pixelsPerSecond,
    required double scrollOffset,
  }) =>
      playheadOffset + timeToPixels(seconds, pixelsPerSecond) - scrollOffset;
}
