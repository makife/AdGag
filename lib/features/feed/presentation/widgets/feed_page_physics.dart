import "package:flutter/widgets.dart";

/// Vertical Ad paging that turns the page on a light swipe (user report:
/// "it takes two swipes to get to the next video").
///
/// The stock PageScrollPhysics only commits to the next page past the
/// halfway point or on a fling above the framework's fling threshold, so
/// a short, slow-ish swipe snapped back. Here: any fling faster than
/// [_flingVelocity] px/s, or a drag past [_dragFraction] of the page,
/// moves one page in the swipe's direction — and never more than one.
///
/// The page settles on a stiffer, critically damped spring than the stock
/// one (which eased in slowly and looked soft next to Instagram — owner):
/// a quick, clean stop with no overshoot, about a quarter second.
class FeedPagePhysics extends PageScrollPhysics {
  const FeedPagePhysics({super.parent});

  static const double _flingVelocity = 200;
  static const double _dragFraction = 0.12;

  static final SpringDescription _settleSpring =
      SpringDescription.withDampingRatio(mass: 0.5, stiffness: 320, ratio: 1.0);

  @override
  SpringDescription get spring => _settleSpring;

  @override
  FeedPagePhysics applyTo(ScrollPhysics? ancestor) => FeedPagePhysics(parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final double pageSize = position.viewportDimension;
    if (pageSize <= 0) {
      return super.createBallisticSimulation(position, velocity);
    }
    final double page = position.pixels / pageSize;
    final double base = page.floorToDouble();
    final double fraction = page - base; // how far into the gap between page `base` and `base + 1`

    double target;
    if (velocity > _flingVelocity) {
      target = base + 1;
    } else if (velocity < -_flingVelocity) {
      target = base;
    } else if (fraction > 1 - _dragFraction) {
      target = base + 1;
    } else if (fraction < _dragFraction) {
      target = base;
    } else {
      // A slow drag that stopped mid-way: go where it was heading.
      target = velocity >= 0 ? base + 1 : base;
      if (velocity == 0) {
        target = page.roundToDouble();
      }
    }
    final double targetPixels = (target * pageSize).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((targetPixels - position.pixels).abs() < toleranceFor(position).distance) {
      return null;
    }
    return ScrollSpringSimulation(spring, position.pixels, targetPixels, velocity, tolerance: toleranceFor(position));
  }
}
