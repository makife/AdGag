import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/theme/app_colors.dart";
import "../../core/theme/app_spacing.dart";
import "../../features/feed/presentation/providers/sold_providers.dart";
import "count_label.dart";

/// SOLD action (CLAUDE.md section 7/64). [baseSoldCount] is the count as
/// fetched into the feed page, which already reflects the current viewer's
/// own past reaction if any. This widget adjusts that base by whatever has
/// changed *since* the async "am I sold" check resolved, so the number
/// updates instantly on tap without a full ad-row refetch (section 41) —
/// it is a display estimate, not a second source of truth; the next feed
/// fetch reconciles it against the server's real count (section 58).
class SoldButton extends ConsumerStatefulWidget {
  const SoldButton({required this.adId, required this.baseSoldCount, super.key});

  final String adId;
  final int baseSoldCount;

  @override
  ConsumerState<SoldButton> createState() => _SoldButtonState();
}

class _SoldButtonState extends ConsumerState<SoldButton> {
  bool? _baseline;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<bool> soldAsync = ref.watch(soldControllerProvider(widget.adId));

    ref.listen<AsyncValue<bool>>(soldControllerProvider(widget.adId), (previous, next) {
      // Capture the first resolved value as the baseline the fetched
      // baseSoldCount already accounted for.
      if (_baseline == null && next.hasValue) {
        setState(() => _baseline = next.value);
      }
    });
    if (_baseline == null && soldAsync.hasValue) {
      _baseline = soldAsync.value;
    }

    final bool isSold = soldAsync.valueOrNull ?? false;
    final int baselineAdjustment = (isSold ? 1 : 0) - ((_baseline ?? isSold) ? 1 : 0);
    final int displayCount = widget.baseSoldCount + baselineAdjustment;

    return Semantics(
      button: true,
      label: isSold ? "Un-SOLD" : "SOLD",
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () async {
          try {
            await ref.read(soldControllerProvider(widget.adId).notifier).toggle();
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Couldn't update SOLD right now.")),
              );
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                isSold ? Icons.sell : Icons.sell_outlined,
                color: isSold ? AppColors.sold : Colors.white,
                size: 28,
              ),
              const SizedBox(height: AppSpacing.xs),
              CountLabel(count: displayCount, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
