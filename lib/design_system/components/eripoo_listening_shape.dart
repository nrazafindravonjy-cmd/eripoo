import 'package:flutter/material.dart';

import '../tokens/eripoo_motion.dart';
import 'eripoo_organic_shape.dart';

/// While a voice answer is being recorded: the organic form breathes
/// gently, so it is obvious that the phone is listening. Still when the
/// user asks for reduced motion. Decorative: the recording state is also
/// said in text next to it.
class EripooListeningShape extends StatefulWidget {
  const EripooListeningShape({super.key, this.size = 120});

  final double size;

  @override
  State<EripooListeningShape> createState() => _EripooListeningShapeState();
}

class _EripooListeningShapeState extends State<EripooListeningShape>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (EripooMotion.of(context).reduced) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shape = EripooOrganicShape(size: widget.size, seed: 11);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.scale(
        scale: 0.9 + 0.12 * Curves.easeInOut.transform(_controller.value),
        child: Transform.rotate(angle: 0.25 * _controller.value, child: child),
      ),
      child: shape,
    );
  }
}
