import 'package:flutter/material.dart';

/// Type scale. Uses the system font (Roboto on Android): no font is bundled,
/// to keep the APK small and start-up fast on entry-level phones.
///
/// Body text is slightly larger than the Material default (17 sp) for
/// readability; all sizes scale with the user's system font size.
abstract final class EripooTypography {
  static TextTheme textTheme(Color primary, Color secondary) {
    TextStyle style(
      double size,
      double height,
      FontWeight weight, {
      Color? color,
    }) => TextStyle(
      fontSize: size,
      height: height / size,
      fontWeight: weight,
      color: color ?? primary,
      letterSpacing: 0,
    );

    return TextTheme(
      displaySmall: style(32, 40, FontWeight.w700),
      headlineMedium: style(26, 34, FontWeight.w700),
      headlineSmall: style(22, 30, FontWeight.w700),
      titleLarge: style(20, 28, FontWeight.w600),
      titleMedium: style(17, 24, FontWeight.w600),
      titleSmall: style(15, 22, FontWeight.w600),
      bodyLarge: style(17, 26, FontWeight.w400),
      bodyMedium: style(15, 22, FontWeight.w400),
      bodySmall: style(13, 18, FontWeight.w400, color: secondary),
      labelLarge: style(16, 20, FontWeight.w600),
      labelMedium: style(14, 18, FontWeight.w600),
      labelSmall: style(12, 16, FontWeight.w600, color: secondary),
    );
  }
}
