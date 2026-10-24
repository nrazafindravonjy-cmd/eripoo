import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Signature shape of Eripoo, taken from the logo: three rounded corners
/// and the bottom-right corner cut on a diagonal, like the speech bubble
/// of the mark. Used by cards, buttons, dialogs and messages.
class EripooCutBorder extends OutlinedBorder {
  const EripooCutBorder({this.radius = 16, this.cut = 20, super.side});

  /// Radius of the three rounded corners.
  final double radius;

  /// Height of the diagonal cut; its width is [cut] × 1.6, the slope of
  /// the logo.
  final double cut;

  static const _slope = 1.6;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  Path _path(Rect rect) {
    final r = math.min(radius, rect.shortestSide / 2);
    final c = math.min(cut, rect.height / 2);
    final cw = math.min(c * _slope, rect.width / 2);
    return Path()
      ..moveTo(rect.left + r, rect.top)
      ..lineTo(rect.right - r, rect.top)
      ..quadraticBezierTo(rect.right, rect.top, rect.right, rect.top + r)
      ..lineTo(rect.right, rect.bottom - c)
      ..lineTo(rect.right - cw, rect.bottom)
      ..lineTo(rect.left + r, rect.bottom)
      ..quadraticBezierTo(rect.left, rect.bottom, rect.left, rect.bottom - r)
      ..lineTo(rect.left, rect.top + r)
      ..quadraticBezierTo(rect.left, rect.top, rect.left + r, rect.top)
      ..close();
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.width));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(
      _path(rect.deflate(side.width / 2)),
      side.toPaint()..style = PaintingStyle.stroke,
    );
  }

  @override
  EripooCutBorder copyWith({BorderSide? side, double? radius, double? cut}) =>
      EripooCutBorder(
        side: side ?? this.side,
        radius: radius ?? this.radius,
        cut: cut ?? this.cut,
      );

  @override
  ShapeBorder scale(double t) =>
      EripooCutBorder(side: side.scale(t), radius: radius * t, cut: cut * t);

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is EripooCutBorder
      ? EripooCutBorder(
          side: BorderSide.lerp(a.side, side, t),
          radius: _lerp(a.radius, radius, t),
          cut: _lerp(a.cut, cut, t),
        )
      : super.lerpFrom(a, t);

  @override
  bool operator ==(Object other) =>
      other is EripooCutBorder &&
      other.side == side &&
      other.radius == radius &&
      other.cut == cut;

  @override
  int get hashCode => Object.hash(side, radius, cut);
}

/// The Eripoo mark as a path filling [rect] (traced from the owner's logo
/// file, 2026-10-23): shared by the logo and the navigation indicator.
Path eripooMarkPath(Rect rect) {
  const w = 1328.0;
  const h = 1380.0;
  final sx = rect.width / w;
  final sy = rect.height / h;
  Offset p(double x, double y) => Offset(rect.left + x * sx, rect.top + y * sy);
  final a = p(48, 0);
  final path = Path()..moveTo(a.dx, a.dy);
  void line(double x, double y) {
    final o = p(x, y);
    path.lineTo(o.dx, o.dy);
  }

  void quad(double cx, double cy, double x, double y) {
    final c = p(cx, cy);
    final o = p(x, y);
    path.quadraticBezierTo(c.dx, c.dy, o.dx, o.dy);
  }

  line(1280, 0);
  quad(1328, 0, 1328, 48);
  line(1328, 1002);
  line(1010, 1002);
  quad(953, 1002, 900, 1035);
  line(344, 1380);
  line(36, 1380);
  quad(0, 1380, 0, 1344);
  line(0, 48);
  quad(0, 0, 48, 0);
  return path..close();
}

double _lerp(double a, double b, double t) => a + (b - a) * t;
