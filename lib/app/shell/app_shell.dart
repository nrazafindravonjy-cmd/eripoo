import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/design_system.dart';
import '../../features/tools/presentation/tools_providers.dart';
import '../../l10n/generated/app_localizations.dart';

/// Top-level shell: the five main sections, adaptive to the window width.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // A dot on Tools while a newly unlocked tool has not been seen.
    final newTools = ref.watch(newToolsProvider);
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
          dot: newTools > 0,
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
