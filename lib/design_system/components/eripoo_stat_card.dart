import 'package:flutter/material.dart';

import '../theme/eripoo_theme.dart';
import '../tokens/eripoo_dimens.dart';
import 'eripoo_card.dart';

/// A compact figure of the project: an icon in a medallion, a label, a
/// large value in the serif face and an optional change badge ("+2 this
/// week"), said in words, never by colour alone. Tappable to open the
/// matching tool.
class EripooStatCard extends StatelessWidget {
  const EripooStatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.badge,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.textStyles;
    final badge = this.badge;
    return EripooCard(
      onTap: onTap,
      semanticLabel: [label, value, ?badge].join(', '),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: t.labelMedium?.copyWith(color: c.textSecondary),
                ),
              ),
              const SizedBox(width: EripooSpacing.xs),
              ExcludeSemantics(
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c.surfaceMuted,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 18, color: c.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: EripooSpacing.sm),
          Text(value, style: t.headlineMedium),
          if (badge != null) ...[
            const SizedBox(height: EripooSpacing.xs),
            Row(
              children: [
                Icon(Icons.north_east, size: 14, color: c.success.base),
                const SizedBox(width: EripooSpacing.xxs),
                Flexible(
                  child: Text(
                    badge,
                    style: t.labelSmall?.copyWith(color: c.success.base),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
