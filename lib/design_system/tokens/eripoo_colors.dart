import 'package:flutter/material.dart';

/// A semantic colour family: a base colour, the content colour drawn on it,
/// a soft container variant and the content colour drawn on that container.
///
/// Every `on*` pair is checked for WCAG contrast in
/// `test/design_system/contrast_test.dart`.
@immutable
class ToneColors {
  const ToneColors({
    required this.base,
    required this.onBase,
    required this.container,
    required this.onContainer,
  });

  final Color base;
  final Color onBase;
  final Color container;
  final Color onContainer;

  static ToneColors lerp(ToneColors a, ToneColors b, double t) => ToneColors(
    base: Color.lerp(a.base, b.base, t)!,
    onBase: Color.lerp(a.onBase, b.onBase, t)!,
    container: Color.lerp(a.container, b.container, t)!,
    onContainer: Color.lerp(a.onContainer, b.onContainer, t)!,
  );
}

/// Eripoo colour tokens, exposed through `Theme.of(context).extension`.
///
/// This file and `eripoo_theme.dart` are the only places where colour
/// literals are allowed (enforced by `test/architecture`). Widgets read
/// colours through `context.colors`.
@immutable
class EripooColors extends ThemeExtension<EripooColors> {
  const EripooColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.scrim,
    required this.brand,
    required this.accent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
  });

  /// Page background.
  final Color background;

  /// Cards, sheets, dialogs, navigation.
  final Color surface;

  /// Quiet areas inside a surface (help panels, inactive tracks).
  final Color surfaceMuted;

  /// Decorative separators. Not used where a boundary must be perceived.
  final Color border;

  /// Boundaries that identify a control (text fields, outlined buttons):
  /// at least 3:1 against surfaces (WCAG 1.4.11).
  final Color borderStrong;

  final Color textPrimary;
  final Color textSecondary;

  /// Modal barrier.
  final Color scrim;

  /// Primary actions, focus, progress.
  final ToneColors brand;

  /// Celebrations and badges. Never used as text on a surface.
  final ToneColors accent;
  final ToneColors success;
  final ToneColors warning;
  final ToneColors danger;
  final ToneColors info;

  /// The Eripoo palette (dark only, owner's decision 2026-10-23): brand
  /// background #232123 and brand yellow #FDCB20.
  static const dark = EripooColors(
    background: Color(0xFF232123),
    surface: Color(0xFF2C2A2C),
    surfaceMuted: Color(0xFF363336),
    border: Color(0xFF433F43),
    borderStrong: Color(0xFF8C878C),
    textPrimary: Color(0xFFF6F3EC),
    textSecondary: Color(0xFFBDB8BD),
    scrim: Color(0xCC000000),
    brand: ToneColors(
      base: Color(0xFFFDCB20),
      onBase: Color(0xFF232123),
      container: Color(0xFF4A3E14),
      onContainer: Color(0xFFFFE78F),
    ),
    accent: ToneColors(
      base: Color(0xFFFFE07A),
      onBase: Color(0xFF232123),
      container: Color(0xFF3F3618),
      onContainer: Color(0xFFFFEDB3),
    ),
    success: ToneColors(
      base: Color(0xFF86DBA0),
      onBase: Color(0xFF0F2E19),
      container: Color(0xFF1E3D29),
      onContainer: Color(0xFFCFF1D9),
    ),
    warning: ToneColors(
      base: Color(0xFFFFB46B),
      onBase: Color(0xFF3A2000),
      container: Color(0xFF4A2E12),
      onContainer: Color(0xFFFFDDBC),
    ),
    danger: ToneColors(
      base: Color(0xFFFF8F85),
      onBase: Color(0xFF4A0F0A),
      container: Color(0xFF5C201C),
      onContainer: Color(0xFFFFDAD5),
    ),
    info: ToneColors(
      base: Color(0xFFA3C6FF),
      onBase: Color(0xFF0E2550),
      container: Color(0xFF1F3456),
      onContainer: Color(0xFFD9E6FF),
    ),
  );

  @override
  EripooColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? scrim,
    ToneColors? brand,
    ToneColors? accent,
    ToneColors? success,
    ToneColors? warning,
    ToneColors? danger,
    ToneColors? info,
  }) => EripooColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceMuted: surfaceMuted ?? this.surfaceMuted,
    border: border ?? this.border,
    borderStrong: borderStrong ?? this.borderStrong,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    scrim: scrim ?? this.scrim,
    brand: brand ?? this.brand,
    accent: accent ?? this.accent,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    info: info ?? this.info,
  );

  @override
  EripooColors lerp(EripooColors? other, double t) {
    if (other == null) return this;
    return EripooColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      brand: ToneColors.lerp(brand, other.brand, t),
      accent: ToneColors.lerp(accent, other.accent, t),
      success: ToneColors.lerp(success, other.success, t),
      warning: ToneColors.lerp(warning, other.warning, t),
      danger: ToneColors.lerp(danger, other.danger, t),
      info: ToneColors.lerp(info, other.info, t),
    );
  }
}

/// Colours that must not follow the theme: QR codes are read by cameras,
/// which need black on white.
abstract final class EripooFixedColors {
  static const qrDark = Color(0xFF000000);
  static const qrLight = Color(0xFFFFFFFF);

  /// The frame drawn over the camera preview.
  static const scannerFrame = Color(0xFFFFFFFF);
}
