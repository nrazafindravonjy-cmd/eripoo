import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/generated/app_localizations.dart';
import '../shapes/eripoo_shapes.dart';
import '../theme/eripoo_theme.dart';
import '../tokens/eripoo_dimens.dart';

/// The main "go on" action, done by sliding the arrow pastille to the
/// right (a deliberate gesture, like confirming a move). A plain tap only
/// nudges the pastille and says "slide to the right". Screen readers and
/// switch access activate it directly (semantic tap), so nobody is locked
/// out by the gesture.
class EripooSwipeAction extends StatefulWidget {
  const EripooSwipeAction({
    super.key,
    required this.label,
    required this.onAction,
    this.isLoading = false,
    this.onDark = false,
  });

  final String label;

  /// Null disables the action.
  final VoidCallback? onAction;
  final bool isLoading;

  /// Dark track on a yellow surface (the hero card), instead of yellow.
  final bool onDark;

  @override
  State<EripooSwipeAction> createState() => _EripooSwipeActionState();
}

class _EripooSwipeActionState extends State<EripooSwipeAction>
    with SingleTickerProviderStateMixin {
  static const _height = EripooLayout.primaryActionHeight;
  static const _knob = 44.0;
  static const _inset = 6.0;

  /// 0 (start) to 1 (end of the track).
  double _progress = 0;
  bool _hint = false;
  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(() => setState(() => _progress = _from * (1 - _back.value)));
  double _from = 0;

  bool get _enabled => widget.onAction != null && !widget.isLoading;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _release() {
    if (_progress > 0.75 && _enabled) {
      HapticFeedback.mediumImpact();
      widget.onAction!();
    }
    _from = _progress;
    _back.forward(from: 0);
  }

  void _nudge() {
    if (!_enabled) return;
    HapticFeedback.selectionClick();
    setState(() => _hint = true);
    _from = 0.18;
    _progress = _from;
    _back.forward(from: 0);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _hint = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = AppLocalizations.of(context);
    final track = widget.onDark ? c.brand.onBase : c.brand.base;
    final ink = widget.onDark ? c.textPrimary : c.brand.onBase;
    final knob = widget.onDark ? c.brand.base : c.brand.onBase;
    final arrow = widget.onDark ? c.brand.onBase : c.brand.base;
    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: _enabled ? widget.onAction : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final travel = constraints.maxWidth - _knob - 2 * _inset;
          return GestureDetector(
            onTap: _nudge,
            onHorizontalDragUpdate: _enabled
                // The pastille follows the finger.
                ? (d) => setState(
                    () => _progress =
                        ((d.localPosition.dx - _inset - _knob / 2) / travel)
                            .clamp(0, 1),
                  )
                : null,
            onHorizontalDragEnd: _enabled ? (_) => _release() : null,
            child: Opacity(
              opacity: widget.onAction == null ? 0.5 : 1,
              child: Container(
                width: double.infinity,
                height: _height,
                decoration: ShapeDecoration(
                  color: track,
                  shape: const EripooCutBorder(radius: EripooRadii.lg, cut: 14),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Opacity(
                      opacity: (1 - _progress * 1.4).clamp(0, 1),
                      child: Padding(
                        padding: const EdgeInsets.only(left: _knob),
                        child: Text(
                          _hint ? l10n.swipeHint : widget.label,
                          style: context.textStyles.labelLarge?.copyWith(
                            color: ink,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: _inset + travel * _progress,
                      child: Container(
                        width: _knob,
                        height: _knob,
                        decoration: BoxDecoration(
                          color: knob,
                          shape: BoxShape.circle,
                        ),
                        child: widget.isLoading
                            ? Padding(
                                padding: const EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: arrow,
                                ),
                              )
                            : Icon(Icons.arrow_forward, size: 20, color: arrow),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
