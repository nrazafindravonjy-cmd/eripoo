import 'package:flutter/material.dart';

import '../shapes/eripoo_shapes.dart';
import '../theme/eripoo_theme.dart';
import '../tokens/eripoo_dimens.dart';
import '../tokens/eripoo_motion.dart';

/// A floating bar shown while items are selected: how many, the one
/// action, and a way out. Slides away when nothing is selected.
class EripooSelectionBar extends StatelessWidget {
  const EripooSelectionBar({
    super.key,
    required this.visible,
    required this.countLabel,
    required this.actionLabel,
    required this.onAction,
    required this.clearLabel,
    required this.onClear,
  });

  final bool visible;
  final String countLabel;
  final String actionLabel;
  final VoidCallback onAction;
  final String clearLabel;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = EripooMotion.of(context);
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 1.5),
      duration: motion.normal,
      curve: motion.standard,
      child: Visibility(
        visible: visible,
        maintainState: true,
        maintainAnimation: true,
        child: Padding(
          padding: const EdgeInsets.all(EripooSpacing.lg),
          child: Material(
            color: c.textPrimary,
            shape: const EripooCutBorder(radius: EripooRadii.xl, cut: 16),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: EripooSpacing.sm,
                vertical: EripooSpacing.xs,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: clearLabel,
                    onPressed: onClear,
                    icon: Icon(Icons.close, color: c.background),
                  ),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        countLabel,
                        style: context.textStyles.titleSmall?.copyWith(
                          color: c.background,
                        ),
                      ),
                    ),
                  ),
                  FilledButton(onPressed: onAction, child: Text(actionLabel)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
