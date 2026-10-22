import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../theme/eripoo_theme.dart';
import '../tokens/eripoo_dimens.dart';

/// A badge medallion. Earned badges use the accent tone; badges still to
/// earn are shown muted, never hidden (they show what can be done next).
class EripooBadge extends StatelessWidget {
  const EripooBadge({
    super.key,
    required this.name,
    required this.icon,
    required this.earned,
    this.size = 72,
  });

  final String name;
  final IconData icon;
  final bool earned;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: earned ? l10n.badgeEarned(name) : l10n.badgeLocked(name),
      excludeSemantics: true,
      child: SizedBox(
        width: size + EripooSpacing.xl,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: earned ? colors.accent.container : colors.surfaceMuted,
                border: Border.all(
                  color: earned ? colors.accent.base : colors.border,
                  width: EripooLayout.borderFocus,
                ),
              ),
              child: Icon(
                earned ? icon : Icons.lock_outline,
                size: size / 2,
                color: earned
                    ? colors.accent.onContainer
                    : colors.textSecondary,
              ),
            ),
            const SizedBox(height: EripooSpacing.sm),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.labelMedium?.copyWith(
                color: earned ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
