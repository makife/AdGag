import "package:flutter/material.dart";

/// Formats engagement counts the way the product spec shows them —
/// `12.8K SOLD`, not `12842 SOLD` (CLAUDE.md section 6/7).
class CountLabel extends StatelessWidget {
  const CountLabel({required this.count, required this.color, super.key});

  final int count;
  final Color color;

  static String format(int count) {
    if (count < 1000) {
      return "$count";
    }
    if (count < 1000000) {
      return "${(count / 1000).toStringAsFixed(1)}K";
    }
    return "${(count / 1000000).toStringAsFixed(1)}M";
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      format(count),
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    );
  }
}
