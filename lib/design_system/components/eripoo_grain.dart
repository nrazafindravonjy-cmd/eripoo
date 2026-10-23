import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../theme/eripoo_theme.dart';

/// A very light film grain over the whole app, for a paper-like matter
/// instead of a flat digital fill. Drawn once (fixed seed) and cached, it
/// never repaints; it ignores touches and is invisible to screen readers.
class EripooGrain extends StatelessWidget {
  const EripooGrain({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _GrainPainter(context.colors.textPrimary),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GrainPainter extends CustomPainter {
  _GrainPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(7);
    final count = (size.width * size.height / 90).round();
    final points = [
      for (var i = 0; i < count; i++)
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
    ];
    canvas.drawPoints(
      PointMode.points,
      points,
      Paint()
        ..color = color.withValues(alpha: 0.035)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.color != color;
}
