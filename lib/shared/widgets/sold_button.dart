import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/analytics/ad_event_type.dart";
import "../../core/analytics/analytics_providers.dart";
import "../../core/theme/app_colors.dart";
import "../../core/theme/app_spacing.dart";
import "../../features/feed/presentation/providers/sold_providers.dart";
import "action_rail_icon.dart";
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

class _SoldButtonState extends ConsumerState<SoldButton> with SingleTickerProviderStateMixin {

  /// Drives the "Sold!" burst (see [_SoldBurst]).
  late final AnimationController _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<bool> soldAsync = ref.watch(soldControllerProvider(widget.adId));

    // The first resolved value is the baseline the fetched baseSoldCount
    // already accounts for (see soldBaselineProvider — it outlives this
    // button). Stored after the frame: providers can't change during build.
    final bool? storedBaseline = ref.watch(soldBaselineProvider(widget.adId));
    if (storedBaseline == null && soldAsync.hasValue) {
      final bool first = soldAsync.value!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final StateController<bool?> baseline = ref.read(soldBaselineProvider(widget.adId).notifier);
        baseline.state ??= first;
      });
    }

    final bool isSold = soldAsync.valueOrNull ?? false;
    final bool baseline = storedBaseline ?? soldAsync.valueOrNull ?? isSold;
    final int baselineAdjustment = (isSold ? 1 : 0) - (baseline ? 1 : 0);
    final int displayCount = widget.baseSoldCount + baselineAdjustment;

    return Semantics(
      button: true,
      label: isSold ? "Un-SOLD" : "SOLD",
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () async {
          // Played on the tap itself (the toggle is optimistic), only when
          // becoming SOLD — never on un-SOLD. Skipped with reduced motion.
          if (!isSold && !MediaQuery.disableAnimationsOf(context)) {
            unawaited(_burst.forward(from: 0));
          }
          try {
            await ref.read(soldControllerProvider(widget.adId).notifier).toggle();
            final bool nowSold = ref.read(soldControllerProvider(widget.adId)).valueOrNull ?? false;
            if (nowSold) {
              ref.read(analyticsServiceProvider).track(widget.adId, AdEventType.sold);
            }
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
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: <Widget>[
                  _SoldBurst(animation: _burst),
                  ActionRailIcon(
                    icon: isSold ? Icons.sell : Icons.sell_outlined,
                    color: isSold ? AppColors.sold : Colors.white,
                    size: 28,
                  ),
                ],
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

/// "Sold!" coming out of the SOLD button: it starts behind the icon, slides
/// to the LEFT at the icon's height while fading in, then fades out after a
/// short slide. The word is a fixed brand word — never translated.
class _SoldBurst extends StatelessWidget {
  const _SoldBurst({required this.animation});

  final Animation<double> animation;

  /// How far left the text travels, in logical pixels.
  static const double _travel = 56;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        final double t = animation.value;
        if (t == 0 || t == 1) {
          return const SizedBox.shrink();
        }
        final double slide = Curves.easeOutCubic.transform(t);
        // Fade in over the first 30%, hold, fade out over the last 45%.
        final double opacity = t < 0.3 ? t / 0.3 : (t > 0.55 ? (1 - t) / 0.45 : 1);
        return Positioned(
          // Right edge starts at the icon's centre, so the word emerges from it.
          right: 20 + slide * _travel,
          child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: child),
        );
      },
      child: const IgnorePointer(
        child: SizedBox(
          height: 40, // the icon's height — the word sits level with it
          child: Center(
            child: Text(
              "Sold!",
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: AppColors.sold,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                letterSpacing: 0.5,
                shadows: <Shadow>[Shadow(color: Colors.black54, blurRadius: 6)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
