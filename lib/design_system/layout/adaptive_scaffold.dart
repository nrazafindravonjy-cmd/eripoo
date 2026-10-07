import 'package:flutter/material.dart';

import '../tokens/eripoo_dimens.dart';
import 'window_size.dart';

/// A top-level destination of the app.
class AdaptiveDestination {
  const AdaptiveDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.dot = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// A small dot on the icon: something new in this section.
  final bool dot;
}

Widget _icon(IconData icon, bool dot) =>
    dot ? Badge(smallSize: 8, child: Icon(icon)) : Icon(icon);

/// App shell: bottom navigation bar on phones, navigation rail on wider
/// windows. One widget tree for both, chosen from the available width.
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
  });

  final List<AdaptiveDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    if (context.windowSize.isCompact) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: _icon(d.icon, d.dot),
                selectedIcon: _icon(d.selectedIcon, d.dot),
                label: d.label,
              ),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          SafeArea(
            right: false,
            child: NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              groupAlignment: -1,
              minWidth: EripooLayout.primaryActionHeight + EripooSpacing.xl,
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(
                    icon: _icon(d.icon, d.dot),
                    selectedIcon: _icon(d.selectedIcon, d.dot),
                    label: Text(d.label),
                  ),
              ],
            ),
          ),
          const VerticalDivider(width: EripooLayout.borderThin),
          Expanded(child: body),
        ],
      ),
    );
  }
}
