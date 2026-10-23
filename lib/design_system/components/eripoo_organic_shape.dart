import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/eripoo_theme.dart';

/// A soft organic form in the brand yellow, lit from the top left so it
/// reads as a volume: the lightweight stand-in for 3D visuals (decision
/// of 2026-10-23). Purely decorative: excluded from screen readers, no
/// animation, a single gradient (cheap on entry-level phones).
class EripooOrganicShape extends StatelessWidget {
  const EripooOrganicShape({super.key, this.size = 160, this.seed = 0});

  final double size;

  /// Varies the outline, so each screen can have its own form.
  final int seed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _OrganicPainter(
          light: c.accent.onContainer,
          base: c.brand.base,
          shade: c.brand.container,
          seed: seed,
        ),
      ),
    );
  }
}

class _OrganicPainter extends CustomPainter {
  _OrganicPainter({
    required this.light,
    required this.base,
    required this.shade,
    required this.seed,
  });

  final Color light;
  final Color base;
  final Color shade;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final random = math.Random(seed);
    const points = 7;
    final offsets = [
      for (var i = 0; i < points; i++) 0.78 + random.nextDouble() * 0.2,
    ];
    Offset at(int i) {
      final angle = 2 * math.pi * i / points;
      final r = radius * offsets[i % points];
      return center + Offset(math.cos(angle) * r, math.sin(angle) * r);
    }

    // Closed smooth curve through the points (midpoint quadratic splines).
    final path = Path();
    for (var i = 0; i <= points; i++) {
      final p = at(i);
      final next = at(i + 1);
      final mid = Offset((p.dx + next.dx) / 2, (p.dy + next.dy) / 2);
      if (i == 0) {
        path.moveTo(mid.dx, mid.dy);
      } else {
        path.quadraticBezierTo(p.dx, p.dy, mid.dx, mid.dy);
      }
    }
    path.close();
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.45, -0.5),
        radius: 1.1,
        colors: [light, base, shade],
        stops: const [0, 0.45, 1],
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_OrganicPainter old) =>
      old.seed != seed || old.base != base;
}
