import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../shapes/eripoo_shapes.dart';
import '../theme/eripoo_theme.dart';

/// Progress drawn as the outline of the Eripoo mark, filled along its
/// contour as [value] goes from 0 to 1, with the figure in the middle.
/// The progress is also given in text next to it (the caller's label).
class EripooProgressMark extends StatelessWidget {
  const EripooProgressMark({
    super.key,
    required this.value,
    required this.center,
    this.size = 72,
    this.color,
    this.trackColor,
  });

  final double value;
  final String center;
  final double size;
  final Color? color;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size * 1.04,
        child: CustomPaint(
          painter: _ProgressMarkPainter(
            value: value.clamp(0, 1),
            color: color ?? c.brand.base,
            track: trackColor ?? c.border,
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: size * 0.15),
              child: Text(
                center,
                style: context.textStyles.titleLarge?.copyWith(
                  color: color ?? c.brand.base,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressMarkPainter extends CustomPainter {
  _ProgressMarkPainter({
    required this.value,
    required this.color,
    required this.track,
  });

  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 5.0;
    final path = eripooMarkPath((Offset.zero & size).deflate(stroke / 2));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint..color = track);
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (s, PathMetric m) => s + m.length);
    var remaining = total * value;
    for (final m in metrics) {
      if (remaining <= 0) break;
      final length = remaining.clamp(0, m.length).toDouble();
      canvas.drawPath(m.extractPath(0, length), paint..color = color);
      remaining -= length;
    }
  }

  @override
  bool shouldRepaint(_ProgressMarkPainter old) =>
      old.value != value || old.color != color || old.track != track;
}
