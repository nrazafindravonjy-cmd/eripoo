import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The mascot's expressions (one image each in assets/mascot/).
enum EripooMood { neutral, happy, focused, disappointed }

/// Whether the mascot is shown below this point (the "Mascot" setting).
/// Absent: hidden, so screens tested on their own stay as they were.
class EripooMascotScope extends InheritedWidget {
  const EripooMascotScope({
    super.key,
    required this.enabled,
    required super.child,
  });

  final bool enabled;

  static bool enabledOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<EripooMascotScope>()
          ?.enabled ??
      false;

  @override
  bool updateShouldNotify(EripooMascotScope old) => old.enabled != enabled;
}

/// Eripoo, the mascot: breathes a few times when it appears, hops when
/// touched (or on [hop], for a victory). Finite animations only, still
/// with reduced motion. Decorative: hidden from screen readers.
class EripooMascot extends StatefulWidget {
  const EripooMascot({
    super.key,
    this.mood = EripooMood.neutral,
    this.height = 160,
    this.hop = false,
  });

  final EripooMood mood;
  final double height;
  final bool hop;

  @override
  State<EripooMascot> createState() => _EripooMascotState();
}

class _EripooMascotState extends State<EripooMascot>
    with TickerProviderStateMixin {
  static const _breaths = 3;

  late final _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final _jump = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  var _left = 0;

  @override
  void initState() {
    super.initState();
    _breath.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _breath.reverse();
      } else if (status == AnimationStatus.dismissed && --_left > 0) {
        _breath.forward();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still || _breath.isAnimating || _jump.isAnimating) return;
    if (widget.hop) {
      _jump.forward(from: 0);
    } else {
      _breathe();
    }
  }

  bool get _still => MediaQuery.disableAnimationsOf(context);

  void _breathe() {
    _left = _breaths;
    _breath.forward(from: 0);
  }

  void _touch() {
    if (_still) return;
    _jump.forward(from: 0);
  }

  @override
  void dispose() {
    _breath.dispose();
    _jump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!EripooMascotScope.enabledOf(context)) return const SizedBox.shrink();
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final image = Image.asset(
      'assets/mascot/${widget.mood.name}.webp',
      // Fixed box (the images are about 3:4) so the layout never jumps
      // while the image decodes.
      width: widget.height * 0.75,
      height: widget.height,
      cacheHeight: (widget.height * ratio).round(),
      fit: BoxFit.contain,
      gaplessPlayback: true,
    );
    return ExcludeSemantics(
      child: GestureDetector(
        onTap: _touch,
        child: AnimatedBuilder(
          animation: Listenable.merge([_breath, _jump]),
          builder: (context, child) {
            final b = Curves.easeInOut.transform(_breath.value);
            // A hop: up then down, with a short squash on landing.
            final j = _jump.value;
            final lift = j < 0.7 ? math.sin(math.pi * j / 0.7) : 0.0;
            final squash = j >= 0.7 ? (1 - (j - 0.7) / 0.3) * 0.06 : 0.0;
            return Transform.translate(
              offset: Offset(0, -lift * widget.height * 0.12),
              child: Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.diagonal3Values(
                  1 + squash,
                  1 + b * 0.025 - squash,
                  1,
                ),
                child: child,
              ),
            );
          },
          child: image,
        ),
      ),
    );
  }
}
