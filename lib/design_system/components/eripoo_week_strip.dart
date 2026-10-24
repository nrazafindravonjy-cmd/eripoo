import 'package:flutter/material.dart';

import '../shapes/eripoo_shapes.dart';
import '../theme/eripoo_theme.dart';
import '../tokens/eripoo_dimens.dart';

/// One day of the week strip.
class EripooDay {
  const EripooDay({
    required this.letter,
    required this.number,
    required this.active,
    required this.semanticLabel,
    this.today = false,
    this.onTap,
  });

  /// Opens the summary of that day.
  final VoidCallback? onTap;

  final String letter;
  final String number;

  /// Something moved forward that day.
  final bool active;
  final bool today;
  final String semanticLabel;
}

/// The last seven days: a small Eripoo mark under each day where the
/// project moved forward. A record of rhythm, never a streak to keep
/// (no count, no penalty: rule 55).
class EripooWeekStrip extends StatelessWidget {
  const EripooWeekStrip({super.key, required this.days});

  final List<EripooDay> days;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.textStyles;
    return Row(
      children: [
        for (final d in days)
          Expanded(
            child: Semantics(
              label: d.semanticLabel,
              button: d.onTap != null,
              excludeSemantics: true,
              child: InkWell(
                onTap: d.onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: EripooSpacing.sm,
                  ),
                  decoration: d.today
                      ? ShapeDecoration(
                          color: c.surfaceMuted,
                          shape: const EripooCutBorder(radius: 14, cut: 8),
                        )
                      : null,
                  child: Column(
                    children: [
                      Text(d.letter, style: t.labelSmall),
                      const SizedBox(height: EripooSpacing.xxs),
                      Text(d.number, style: t.titleSmall),
                      const SizedBox(height: EripooSpacing.xs),
                      CustomPaint(
                        size: const Size(10, 10.4),
                        painter: _DayMarkPainter(
                          d.active ? c.brand.base : c.border,
                          filled: d.active,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DayMarkPainter extends CustomPainter {
  _DayMarkPainter(this.color, {required this.filled});

  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    if (!filled) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
    }
    canvas.drawPath(eripooMarkPath(Offset.zero & size), paint);
  }

  @override
  bool shouldRepaint(_DayMarkPainter old) =>
      old.color != color || old.filled != filled;
}
