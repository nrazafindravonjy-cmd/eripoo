import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/design_system.dart';
import '../../l10n/generated/app_localizations.dart';

/// Top-level shell: the five main sections, adaptive to the window width.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AdaptiveScaffold(
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: (index) => navigationShell.goBranch(
        index,
        // Tapping the current tab again returns to its first screen.
        initialLocation: index == navigationShell.currentIndex,
      ),
      destinations: [
        AdaptiveDestination(
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          label: l10n.navHome,
        ),
        AdaptiveDestination(
          icon: Icons.flag_outlined,
          selectedIcon: Icons.flag,
          label: l10n.navQuest,
        ),
        AdaptiveDestination(
          icon: Icons.work_outline,
          selectedIcon: Icons.work,
          label: l10n.navProject,
        ),
        AdaptiveDestination(
          icon: Icons.handyman_outlined,
          selectedIcon: Icons.handyman,
          label: l10n.navTools,
        ),
        AdaptiveDestination(
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
          label: l10n.navProfile,
        ),
      ],
      body: navigationShell,
    );
  }
}
