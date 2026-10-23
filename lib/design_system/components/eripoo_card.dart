import 'package:flutter/material.dart';

import '../tokens/eripoo_dimens.dart';
import '../tokens/eripoo_motion.dart';

/// A surface grouping related content, in the signature shape (the logo's
/// cut corner, from the card theme). Tappable when [onTap] is set: it then
/// sinks slightly under the finger, at once (rule 16).
class EripooCard extends StatefulWidget {
  const EripooCard({
    super.key,
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.padding = const EdgeInsets.all(EripooSpacing.lg),
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Label read by screen readers when the whole card is a single action.
  final String? semanticLabel;
  final EdgeInsetsGeometry padding;

  @override
  State<EripooCard> createState() => _EripooCardState();
}

class _EripooCardState extends State<EripooCard> {
  bool _pressed = false;

  void _press(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: widget.padding, child: widget.child);
    final onTap = widget.onTap;
    final card = Card(
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? body
          : Semantics(
              button: true,
              label: widget.semanticLabel,
              child: InkWell(
                onTap: onTap,
                onHighlightChanged: _press,
                child: body,
              ),
            ),
    );
    if (onTap == null) return card;
    final motion = EripooMotion.of(context);
    return AnimatedScale(
      scale: _pressed && !motion.reduced ? 0.98 : 1,
      duration: motion.fast,
      curve: motion.standard,
      child: card,
    );
  }
}
