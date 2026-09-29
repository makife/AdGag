import "package:flutter/material.dart";

import "../../../../shared/widgets/count_label.dart";

/// One number + label in a profile's stats row (Ads / Followers /
/// Following). Tappable when [onTap] is set (the follow counts open their
/// lists), with a tap target of at least 48dp.
class ProfileStat extends StatelessWidget {
  const ProfileStat({required this.label, required this.value, this.onTap, super.key});

  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(CountLabel.format(value), style: Theme.of(context).textTheme.titleMedium),
              Text(label, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}
