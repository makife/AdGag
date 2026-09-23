import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:go_router/go_router.dart";

import "../../features/create_ad/presentation/providers/create_ad_flow_controller.dart";
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
  static const double barHeight = 56;

  static const List<_TabSpec> _tabs = <_TabSpec>[
    _TabSpec(icon: Icons.home_outlined, selectedIcon: Icons.home, label: "Home"),
    _TabSpec(icon: Icons.storefront_outlined, selectedIcon: Icons.storefront, label: "Market"),
    _TabSpec(icon: null, selectedIcon: null, label: "AD"), // central branded action
    _TabSpec(icon: Icons.bolt_outlined, selectedIcon: Icons.bolt, label: "Activity"),
    _TabSpec(icon: Icons.person_outline, selectedIcon: Icons.person, label: "Profile"),
  ];

  /// The AD tab's index in [_tabs] — the one screen ([TrimStep]) that can
  /// have in-progress, losable edits when the user switches away from it.
  static const int _createTabIndex = 2;

  Future<void> _onTabTap(BuildContext context, WidgetRef ref, int index) async {
    final bool leavingCreateTab = navigationShell.currentIndex == _createTabIndex && index != _createTabIndex;
    if (leavingCreateTab && ref.read(hasUnsavedCreateEditsProvider)) {
      final bool? leave = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text("Leave without finishing?"),
          content: const Text("You'll lose the edits you made to this Ad."),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text("Stay")),
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text("Leave")),
          ],
        ),
      );
      if (leave != true) {
        return;
      }
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

    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
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
                          width: 44,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: AppColors.brandGradient,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: const Text(
                            "AD",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
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
                      label: tab.label,
                      selected: isSelected,
                      button: true,
                      child: Icon(
                        isSelected ? tab.selectedIcon : tab.icon,
                        color: isSelected
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                        size: 24,
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

class _TabSpec {
  const _TabSpec({required this.icon, required this.selectedIcon, required this.label});
  final IconData? icon;
  final IconData? selectedIcon;
  final String label;
}
