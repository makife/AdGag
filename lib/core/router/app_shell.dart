import "package:flutter/material.dart";
import "package:go_router/go_router.dart";

import "../theme/app_colors.dart";
import "../theme/app_spacing.dart";

/// Bottom navigation shell (CLAUDE.md section 5): HOME, MARKET, AD (central
/// creation action), ACTIVITY, PROFILE. Built on [StatefulShellRoute] so
/// each tab keeps its own navigation stack and scroll position when
/// switching tabs — important for the feed, which must not rebuild/reset
/// on every tab switch (section 41).
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const List<_TabSpec> _tabs = <_TabSpec>[
    _TabSpec(icon: Icons.home_outlined, selectedIcon: Icons.home, label: "Home"),
    _TabSpec(icon: Icons.storefront_outlined, selectedIcon: Icons.storefront, label: "Market"),
    _TabSpec(icon: null, selectedIcon: null, label: "AD"), // central branded action
    _TabSpec(icon: Icons.bolt_outlined, selectedIcon: Icons.bolt, label: "Activity"),
    _TabSpec(icon: Icons.person_outline, selectedIcon: Icons.person, label: "Profile"),
  ];

  @override
  Widget build(BuildContext context) {
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
            height: 56,
            child: Row(
              children: List<Widget>.generate(_tabs.length, (int index) {
                final _TabSpec tab = _tabs[index];
                final bool isSelected = navigationShell.currentIndex == index;

                if (tab.icon == null) {
                  // Central AD action — deliberately not a generic "+".
                  return Expanded(
                    child: Center(
                      child: GestureDetector(
                        onTap: () => navigationShell.goBranch(index),
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
                    onTap: () => navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex),
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
