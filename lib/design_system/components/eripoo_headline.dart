import 'package:flutter/material.dart';

import '../theme/eripoo_theme.dart';

/// A screen title in the editorial style: Instrument Serif, with the words
/// between asterisks set in yellow italics, e.g. "Ton *problème*". The
/// asterisks come from the ARB string; screen readers get the plain text.
class EripooHeadline extends StatelessWidget {
  const EripooHeadline(this.text, {super.key, this.style, this.emphasisColor});

  final String text;

  /// Defaults to `headlineMedium`.
  final TextStyle? style;

  /// Defaults to the brand yellow; set it on a yellow surface.
  final Color? emphasisColor;

  /// [text] without the emphasis markers.
  static String plain(String text) => text.replaceAll('*', '');

  @override
  Widget build(BuildContext context) {
    final base = style ?? context.textStyles.headlineMedium!;
    final emphasis = base.copyWith(
      fontStyle: FontStyle.italic,
      color: emphasisColor ?? context.colors.brand.base,
    );
    final parts = text.split('*');
    return Semantics(
      header: true,
      label: plain(text),
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            for (var i = 0; i < parts.length; i++)
              if (parts[i].isNotEmpty)
                TextSpan(text: parts[i], style: i.isOdd ? emphasis : base),
          ],
        ),
        style: base,
      ),
    );
  }
}
