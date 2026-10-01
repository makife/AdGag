import "package:flutter/material.dart";

import "../../../../core/theme/app_colors.dart";

/// A short brand-gradient line on the seam between two Ads while a vertical
/// pager is between pages, moving in step with the swipe: swiping UP (to the
/// next Ad) it travels left -> right, swiping DOWN (back) right -> left
/// (owner's spec). It starts off one edge and leaves off the other as the
/// new Ad settles.
/// Drawn over the pager (ignores touches); nothing is drawn while settled.
class SwipeSeamLine extends StatefulWidget {
  const SwipeSeamLine({required this.controller, super.key});

  final PageController controller;

  @override
  State<SwipeSeamLine> createState() => _SwipeSeamLineState();
}

class _SwipeSeamLineState extends State<SwipeSeamLine> {
  /// The page the current swipe started from (the last settled page).
  int _start = 0;

  static const double _thickness = 3;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) => AnimatedBuilder(
          animation: widget.controller,
          builder: (BuildContext context, Widget? child) {
            final PageController c = widget.controller;
            if (!c.hasClients || c.positions.length != 1 || !c.position.haveDimensions) {
              return const SizedBox.shrink();
            }
            final ScrollPosition pos = c.position;
            // Overscroll (a bounce, pull-to-refresh) has no seam.
            if (pos.pixels < pos.minScrollExtent || pos.pixels > pos.maxScrollExtent) {
              return const SizedBox.shrink();
            }
            final double page = c.page ?? 0;
            final int settled = page.round();
            if ((page - settled).abs() < 0.002) {
              _start = settled;
              return const SizedBox.shrink();
            }
            final double progress = (page - _start).abs().clamp(0.0, 1.0);
            final bool forward = page > _start; // swiping up, toward the next Ad
            final double width = box.maxWidth;
            final double lineWidth = width * 0.4;
            // The boundary between page floor(page) and the next one.
            final double seamY = (page.floorToDouble() + 1 - page) * box.maxHeight;
            final double travel = forward ? progress : 1 - progress;
            final double x = travel * (width + lineWidth) - lineWidth;
            return Stack(
              children: <Widget>[
                Positioned(
                  left: x,
                  top: seamY - _thickness / 2,
                  width: lineWidth,
                  height: _thickness,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(_thickness),
                      boxShadow: <BoxShadow>[
                        BoxShadow(color: AppColors.brandTurquoise.withValues(alpha: 0.7), blurRadius: 8),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
