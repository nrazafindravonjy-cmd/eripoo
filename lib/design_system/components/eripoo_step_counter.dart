import 'package:flutter/material.dart';

import '../theme/eripoo_theme.dart';
import '../tokens/eripoo_dimens.dart';

/// Where the user is within a step: a large serif figure in yellow, the
/// total beside it, and a thin bar. [semanticLabel] says it in words.
class EripooStepCounter extends StatelessWidget {
  const EripooStepCounter({
    super.key,
    required this.current,
    required this.total,
    required this.semanticLabel,
  });

  final int current;
  final int total;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.textStyles;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$current',
                  style: t.displaySmall?.copyWith(color: c.brand.base),
                ),
                TextSpan(
                  text: ' / $total',
                  style: t.titleMedium?.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: EripooSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(EripooRadii.pill),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : current / total,
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }
}
