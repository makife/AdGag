import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:go_router/go_router.dart";
import "../localization/generated/app_localizations.dart";

import "../../features/create_ad/domain/create_ad_step.dart";
import "../../features/create_ad/presentation/providers/create_ad_flow_controller.dart";
import "../../features/create_ad/presentation/providers/create_ad_flow_state.dart";
import "../theme/app_colors.dart";
import "../theme/app_spacing.dart";

/// Which shell branch (bottom-nav tab) is currently visible. [IndexedStack]
/// (what [StatefulShellRoute.indexedStack] uses under the hood) keeps every
/// branch's widget tree mounted even when it's not the displayed one — it
/// does not pause timers, animations, or playing video on its own. Screens
/// that own playing media (the feed) watch this to pause when their branch
/// is hidden and resume when it becomes visible again (section 17).
final StateProvider<int> activeShellBranchIndexProvider = StateProvider<int>((ref) => 0);

/// Bottom navigation shell (CLAUDE.md section 5): HOME, MARKET, AD (central
/// creation action), ACTIVITY, PROFILE. Built on [StatefulShellRoute] so
/// each tab keeps its own navigation stack and scroll position when
/// switching tabs — important for the feed, which must not rebuild/reset
/// on every tab switch (section 41).
class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  /// The bar's own height, excluding the safe-area inset added around it
  /// below. Screens under it (the feed, via `Scaffold(extendBody: true)`)
  /// need this to keep bottom-anchored content — the action rail,
  /// subject/creator overlay — from sitting behind the (opaque, not
  /// translucent) bar instead of above it.
  static const double minBarHeight = 56;
  static const double maxBarHeight = 88;

  /// The bar's height on this screen. A 9:16 Ad shown full-width under the
  /// status bar leaves a black band below it on today's taller (~9:20)
  /// phones; the bar grows (up to [maxBarHeight]) to fill exactly that band
  /// instead, so the feed is video + bar with no dead space. On shorter
  /// screens it stays at [minBarHeight].
  static double barHeightOf(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final EdgeInsets padding = MediaQuery.paddingOf(context);
    final double videoHeight = size.width * 16 / 9;
    final double gap = size.height - padding.top - videoHeight - padding.bottom;
    return gap.clamp(minBarHeight, maxBarHeight);
  }

  static const List<_TabSpec> _tabs = <_TabSpec>[
    _TabSpec(icon: Icons.home_outlined, selectedIcon: Icons.home, label: _TabLabel.home),
    _TabSpec(icon: Icons.storefront_outlined, selectedIcon: Icons.storefront, label: _TabLabel.market),
    _TabSpec(icon: null, selectedIcon: null, label: _TabLabel.ad), // central branded action
    _TabSpec(icon: Icons.bolt_outlined, selectedIcon: Icons.bolt, label: _TabLabel.activity),
    _TabSpec(icon: Icons.person_outline, selectedIcon: Icons.person, label: _TabLabel.profile),
  ];

  /// The AD tab's index in [_tabs].
  static const int _createTabIndex = 2;

  Future<void> _onTabTap(BuildContext context, WidgetRef ref, int index) async {
    final bool leavingCreateTab = navigationShell.currentIndex == _createTabIndex && index != _createTabIndex;
    // No "lose your edits?" confirmation needed here — editing itself
    // now happens entirely in a native Activity (see NativeEditorStep),
    // which owns and can discard its own in-progress state; nothing
    // losable is ever held in Flutter/Dart state.
    if (leavingCreateTab) {
      // Whether or not there were edits to confirm: leaving the AD tab
      // always starts the flow over from subject selection next time,
      // rather than resuming wherever it was left (CLAUDE.md creation
      // flow, section 38 — a half-finished Ad isn't a draft the flow
      // remembers for you yet).
      ref.read(createAdFlowControllerProvider.notifier).reset();
    }
    navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final StateController<int> activeBranch = ref.read(activeShellBranchIndexProvider.notifier);
      if (activeBranch.state != navigationShell.currentIndex) {
        activeBranch.state = navigationShell.currentIndex;
      }
    });

    // The editor (CreateAdStep.trim) is deliberately immersive — video
    // is the visual focus, per the tightened editor spec's section 12:
    // "No normal AdGag bottom navigation while editing... Video remains
    // the visual focus." Every other create-flow step (subject picker,
    // capture, caption/publish) keeps the normal shell chrome.
    final bool onTrimStep = ref.watch(
      createAdFlowControllerProvider.select((CreateAdFlowState s) => s.step == CreateAdStep.trim),
    );

    final double barHeight = barHeightOf(context);
    // Roomier bar -> bigger icons, and labels once there's space for them.
    final bool roomy = barHeight >= 68;
    final double iconSize = roomy ? 28 : 24;

    return Scaffold(
      extendBody: true,
      // The home feed lays itself out around the keyboard (reviews panel);
      // resizing the whole pager made the open panel jump away.
      resizeToAvoidBottomInset: navigationShell.currentIndex != 0,
      body: navigationShell,
      bottomNavigationBar: onTrimStep
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              child: SafeArea(
                child: SizedBox(
                  height: barHeight,
                  child: Row(
                    children: List<Widget>.generate(_tabs.length, (int index) {
                      final _TabSpec tab = _tabs[index];
                      final bool isSelected = navigationShell.currentIndex == index;

                      if (tab.icon == null) {
                        // Central AD action — deliberately not a generic "+".
                        return Expanded(
                          child: Center(
                            child: GestureDetector(
                              onTap: () => unawaited(_onTabTap(context, ref, index)),
                              child: Container(
                                width: roomy ? 54 : 44,
                                height: roomy ? 38 : 32,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  gradient: AppColors.brandGradient,
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                ),
                                child: Text(
                                  "AD",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: roomy ? 15 : 13,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      return Expanded(
                        child: InkWell(
                          onTap: () => unawaited(_onTabTap(context, ref, index)),
                          child: Semantics(
                            label: tab.label.text(context),
                            selected: isSelected,
                            button: true,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Icon(
                                  isSelected ? tab.selectedIcon : tab.icon,
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.onSurface
                                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                  size: iconSize,
                                ),
                                if (roomy) ...<Widget>[
                                  const SizedBox(height: 2),
                                  Text(
                                    tab.label.text(context),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                      color: isSelected
                                          ? Theme.of(context).colorScheme.onSurface
                                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
    );
  }
}

/// Bottom-nav labels, resolved in the user's language (AD stays AD).
enum _TabLabel {
  home,
  market,
  ad,
  activity,
  profile;

  String text(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return switch (this) {
      _TabLabel.home => l10n.navHome,
      _TabLabel.market => l10n.navMarket,
      _TabLabel.ad => l10n.navAd,
      _TabLabel.activity => l10n.navActivity,
      _TabLabel.profile => l10n.navProfile,
    };
  }
}

class _TabSpec {
  const _TabSpec({required this.icon, required this.selectedIcon, required this.label});
  final IconData? icon;
  final IconData? selectedIcon;
  final _TabLabel label;
}
