import 'package:flutter/material.dart';

import '../shapes/eripoo_shapes.dart';
import '../theme/eripoo_theme.dart';
import '../tokens/eripoo_dimens.dart';

enum EripooPathState { done, current, locked }

/// One stage of a vertical journey: a small Eripoo mark on a line, filled
/// in yellow once done, outlined while open, dim when locked; [child] (a
/// card) sits on its right. The state is also said in text by [child], so
/// colour never carries it alone (rule 38).
class EripooPathItem extends StatelessWidget {
  const EripooPathItem({
    super.key,
    required this.state,
    required this.child,
    this.isFirst = false,
    this.isLast = false,
  });

  final EripooPathState state;
  final Widget child;
  final bool isFirst;
  final bool isLast;

  static const _mark = 22.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final line = c.border;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _mark + EripooSpacing.lg,
            child: Column(
              children: [
                SizedBox(
                  height: EripooSpacing.xl,
                  child: isFirst
                      ? null
                      : Center(child: Container(width: 2, color: line)),
                ),
                ExcludeSemantics(
                  child: CustomPaint(
                    size: const Size(_mark, _mark * 1.04),
                    painter: _MarkPainter(
                      state: state,
                      fill: c.brand.base,
                      outline: state == EripooPathState.locked
                          ? c.border
                          : c.brand.base,
                    ),
                  ),
                ),
                Expanded(
                  child: isLast
                      ? const SizedBox.shrink()
                      : Center(child: Container(width: 2, color: line)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: EripooSpacing.md),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({
    required this.state,
    required this.fill,
    required this.outline,
  });

  final EripooPathState state;
  final Color fill;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final path = eripooMarkPath(Offset.zero & size);
    if (state == EripooPathState.done) {
      canvas.drawPath(path, Paint()..color = fill);
    } else {
      canvas.drawPath(
        path,
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.state != state || old.fill != fill || old.outline != outline;
}
