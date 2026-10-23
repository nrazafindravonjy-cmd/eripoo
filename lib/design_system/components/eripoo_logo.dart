import 'package:flutter/material.dart';

import '../theme/eripoo_theme.dart';

/// The official Eripoo mark (a speech-bubble page with a folded corner),
/// drawn as a vector so it stays sharp at any size and weighs nothing.
/// Traced from the owner's logo file (2026-10-23).
class EripooLogo extends StatelessWidget {
  const EripooLogo({super.key, this.size = 48, this.semanticLabel});

  /// Height of the mark; the width follows its proportions.
  final double size;

  /// Read by screen readers; null when the logo is decorative.
  final String? semanticLabel;

  static const _aspect = _LogoPainter.width / _LogoPainter.height;

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size(size * _aspect, size),
      painter: _LogoPainter(context.colors.brand.base),
    );
    final label = semanticLabel;
    if (label == null) return ExcludeSemantics(child: mark);
    return Semantics(label: label, image: true, child: mark);
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.color);

  final Color color;

  // Units of the traced artwork.
  static const width = 1328.0;
  static const height = 1380.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / width, size.height / height);
    final path = Path()
      ..moveTo(48, 0)
      ..lineTo(1280, 0)
      ..quadraticBezierTo(1328, 0, 1328, 48)
      ..lineTo(1328, 1002)
      ..lineTo(1010, 1002)
      ..quadraticBezierTo(953, 1002, 900, 1035)
      ..lineTo(344, 1380)
      ..lineTo(36, 1380)
      ..quadraticBezierTo(0, 1380, 0, 1344)
      ..lineTo(0, 48)
      ..quadraticBezierTo(0, 0, 48, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.color != color;
}
