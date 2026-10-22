import 'package:flutter/material.dart';

import '../tokens/eripoo_dimens.dart';

/// A bordered surface grouping related content. Flat (no shadow), in the
/// spirit of a structured workspace. Tappable when [onTap] is set.
class EripooCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final body = Padding(padding: padding, child: child);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? body
          : Semantics(
              button: true,
              label: semanticLabel,
              child: InkWell(onTap: onTap, child: body),
            ),
    );
  }
}
