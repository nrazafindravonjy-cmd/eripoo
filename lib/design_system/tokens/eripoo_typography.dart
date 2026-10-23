import 'package:flutter/material.dart';

/// Type scale: Instrument Serif for display and headings (the brand
/// voice), Jost for everything people read or tap. Both bundled (SIL OFL,
/// assets/fonts/), so the app looks the same offline on every phone.
/// Instrument Serif has one weight; Jost is a variable font, so its
/// weight is set through the `wght` axis as well.
///
/// Body text is 17 sp for readability; all sizes scale with the user's
/// system font size.
abstract final class EripooTypography {
  static const serif = 'InstrumentSerif';
  static const sans = 'Jost';

  static TextTheme textTheme(Color primary, Color secondary) {
    TextStyle display(double size, double height) => TextStyle(
      fontFamily: serif,
      fontSize: size,
      height: height / size,
      fontWeight: FontWeight.w400,
      color: primary,
      letterSpacing: -0.2,
    );
    TextStyle sans(double size, double height, int weight, {Color? color}) =>
        TextStyle(
          fontFamily: EripooTypography.sans,
          fontSize: size,
          height: height / size,
          fontWeight: FontWeight.values[weight ~/ 100 - 1],
          fontVariations: [FontVariation('wght', weight.toDouble())],
          color: color ?? primary,
          letterSpacing: 0,
        );

    return TextTheme(
      displaySmall: display(40, 46),
      headlineMedium: display(32, 38),
      headlineSmall: display(26, 32),
      titleLarge: display(24, 30),
      titleMedium: sans(17, 24, 600),
      titleSmall: sans(15, 22, 600),
      bodyLarge: sans(17, 26, 400),
      bodyMedium: sans(15, 22, 400),
      bodySmall: sans(13, 18, 400, color: secondary),
      labelLarge: sans(16, 20, 600),
      labelMedium: sans(14, 18, 600),
      labelSmall: sans(12, 16, 600, color: secondary),
    );
  }
}
