import 'package:flutter/material.dart';

import '../theme/eripoo_theme.dart';
import '../tokens/eripoo_dimens.dart';

/// Up to four key figures side by side, separated by hairlines: a grey
/// label above a yellow value. Read before starting something.
class EripooMetrics extends StatelessWidget {
  const EripooMetrics({super.key, required this.items});

  /// (label, value) pairs.
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.textStyles;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: c.border)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (final (i, (label, value)) in items.indexed) ...[
              if (i > 0) VerticalDivider(width: 1, color: c.border),
              Expanded(
                child: Semantics(
                  label: '$label : $value',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: EripooSpacing.md,
                      horizontal: EripooSpacing.xs,
                    ),
                    child: Column(
                      children: [
                        Text(label, style: t.labelSmall),
                        const SizedBox(height: EripooSpacing.xxs),
                        Text(
                          value,
                          style: t.titleSmall?.copyWith(color: c.brand.base),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
