import 'package:flutter/material.dart';

import '../tokens/eripoo_motion.dart';
import 'eripoo_logo.dart';

/// Confirmation of a completed step: the Eripoo mark appears in yellow
/// (≈ 300 ms), instead of a generic tick. Static with reduced motion.
class EripooDoneMark extends StatelessWidget {
  const EripooDoneMark({
    super.key,
    this.size = 40,
    this.semanticLabel,
    this.color,
  });

  /// Defaults to the brand yellow.
  final Color? color;

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final motion = EripooMotion.of(context);
    final logo = EripooLogo(
      size: size,
      semanticLabel: semanticLabel,
      color: color,
    );
    if (motion.reduced) return logo;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motion.slow,
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
      ),
      child: logo,
    );
  }
}
