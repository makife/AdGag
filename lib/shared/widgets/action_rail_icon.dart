import "package:flutter/material.dart";

/// A circular dark backdrop behind a feed action-rail icon (CLAUDE.md
/// section 64 design system). A bare icon sitting directly on top of
/// video content has inconsistent contrast depending on what frame is
/// underneath it — a consistent circular scrim fixes that and gives each
/// action a clearer, more deliberately-tappable target, matching what
/// [SoldButton]/[ReviewButton]/[AdThisButton]/[ShareButton]/
/// [MoreMenuButton] all render behind their own icon.
class ActionRailIcon extends StatelessWidget {
  const ActionRailIcon({required this.icon, this.color = Colors.white, this.size = 26, super.key});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
      child: Icon(icon, color: color, size: size),
    );
  }
}
