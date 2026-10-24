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
class AdaptiveScaffold extends StatefulWidget {
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
  State<AdaptiveScaffold> createState() => _AdaptiveScaffoldState();
}

class _AdaptiveScaffoldState extends State<AdaptiveScaffold> {
  /// Counts taps, so the selected icon pops at every tap (even on the tab
  /// already open).
  int _taps = 0;

  void _select(int index) {
    setState(() => _taps++);
    widget.onDestinationSelected(index);
  }

  Widget _selected(IconData icon, bool dot) =>
      _PopIcon(key: ValueKey(_taps), child: _icon(icon, dot));

  @override
  Widget build(BuildContext context) {
    final destinations = widget.destinations;
    final selectedIndex = widget.selectedIndex;
    final body = widget.body;
    if (context.windowSize.isCompact) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: _select,
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: _icon(d.icon, d.dot),
                selectedIcon: _selected(d.selectedIcon, d.dot),
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
              onDestinationSelected: _select,
              groupAlignment: -1,
              minWidth: EripooLayout.primaryActionHeight + EripooSpacing.xl,
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(
                    icon: _icon(d.icon, d.dot),
                    selectedIcon: _selected(d.selectedIcon, d.dot),
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

/// A subtle pop of the selected icon (scale 0.8 → 1), at each tap; still
/// with reduced motion.
class _PopIcon extends StatelessWidget {
  const _PopIcon({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.8, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: child,
    );
  }
}
