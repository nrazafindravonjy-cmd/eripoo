import 'package:flutter/material.dart';

import '../shapes/eripoo_shapes.dart';
import '../theme/eripoo_theme.dart';
import '../tokens/eripoo_dimens.dart';

/// A full-width navigation line: icon, label, an arrow in a small
/// cut-corner square, and a hairline under it. For secondary entries, so
/// they never look like content cards.
class EripooNavRow extends StatelessWidget {
  const EripooNavRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: EripooLayout.primaryActionHeight,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          padding: const EdgeInsets.symmetric(vertical: EripooSpacing.sm),
          child: Row(
            children: [
              Icon(icon, color: iconColor ?? c.textSecondary),
              const SizedBox(width: EripooSpacing.md),
              Expanded(child: Text(label, style: context.textStyles.bodyLarge)),
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: c.surfaceMuted,
                  shape: const EripooCutBorder(radius: 8, cut: 6),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(EripooSpacing.xs),
                  child: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
