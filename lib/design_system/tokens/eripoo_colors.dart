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

  static const light = EripooColors(
    background: Color(0xFFFAFAF7),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF2F2EE),
    border: Color(0xFFD9D9D2),
    borderStrong: Color(0xFF7D7F78),
    textPrimary: Color(0xFF1B1C1A),
    textSecondary: Color(0xFF5C5E58),
    scrim: Color(0x80000000),
    brand: ToneColors(
      base: Color(0xFF0B6E5F),
      onBase: Color(0xFFFFFFFF),
      container: Color(0xFFD3F0EA),
      onContainer: Color(0xFF053D35),
    ),
    accent: ToneColors(
      base: Color(0xFFE8A317),
      onBase: Color(0xFF1B1C1A),
      container: Color(0xFFFCEFD0),
      onContainer: Color(0xFF5A3D00),
    ),
    success: ToneColors(
      base: Color(0xFF1E7A3C),
      onBase: Color(0xFFFFFFFF),
      container: Color(0xFFDDF3E4),
      onContainer: Color(0xFF0E4021),
    ),
    warning: ToneColors(
      base: Color(0xFF8A5A00),
      onBase: Color(0xFFFFFFFF),
      container: Color(0xFFFFF1D6),
      onContainer: Color(0xFF4D3200),
    ),
    danger: ToneColors(
      base: Color(0xFFB3261E),
      onBase: Color(0xFFFFFFFF),
      container: Color(0xFFF9DEDC),
      onContainer: Color(0xFF5C1411),
    ),
    info: ToneColors(
      base: Color(0xFF2457C5),
      onBase: Color(0xFFFFFFFF),
      container: Color(0xFFDCE6FB),
      onContainer: Color(0xFF0E2C6B),
    ),
  );

  static const dark = EripooColors(
    background: Color(0xFF121412),
    surface: Color(0xFF1A1C1A),
    surfaceMuted: Color(0xFF242723),
    border: Color(0xFF4A4E48),
    borderStrong: Color(0xFF7E8179),
    textPrimary: Color(0xFFECEDE8),
    textSecondary: Color(0xFFB0B2AB),
    scrim: Color(0xB3000000),
    brand: ToneColors(
      base: Color(0xFF5CCFB9),
      onBase: Color(0xFF00382F),
      container: Color(0xFF12493F),
      onContainer: Color(0xFFC6F1E8),
    ),
    accent: ToneColors(
      base: Color(0xFFF5BE4A),
      onBase: Color(0xFF2A1C00),
      container: Color(0xFF4A3500),
      onContainer: Color(0xFFFCE3A8),
    ),
    success: ToneColors(
      base: Color(0xFF6FD08C),
      onBase: Color(0xFF00391A),
      container: Color(0xFF12452A),
      onContainer: Color(0xFFC4EED1),
    ),
    warning: ToneColors(
      base: Color(0xFFF0C05A),
      onBase: Color(0xFF3A2700),
      container: Color(0xFF4A3500),
      onContainer: Color(0xFFFCE3A8),
    ),
    danger: ToneColors(
      base: Color(0xFFF2B8B5),
      onBase: Color(0xFF601410),
      container: Color(0xFF8C1D18),
      onContainer: Color(0xFFF9DEDC),
    ),
    info: ToneColors(
      base: Color(0xFFA9C3F8),
      onBase: Color(0xFF0E2C6B),
      container: Color(0xFF1E3E8A),
      onContainer: Color(0xFFDCE6FB),
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
/// which need black on white in light and dark mode alike.
abstract final class EripooFixedColors {
  static const qrDark = Color(0xFF000000);
  static const qrLight = Color(0xFFFFFFFF);

  /// The frame drawn over the camera preview.
  static const scannerFrame = Color(0xFFFFFFFF);
}
