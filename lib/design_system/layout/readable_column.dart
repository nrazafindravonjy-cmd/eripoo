import 'package:flutter/widgets.dart';

import '../tokens/eripoo_dimens.dart';
import 'window_size.dart';

/// Centres its child in a reading column: page gutters on every width, and
/// a maximum width so lines stay short on tablets.
class ReadableColumn extends StatelessWidget {
  const ReadableColumn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.windowSize.gutter),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: EripooLayout.maxReadableWidth,
          ),
          child: child,
        ),
      ),
    );
  }
}
