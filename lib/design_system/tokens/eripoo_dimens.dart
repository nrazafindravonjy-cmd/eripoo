/// Spacing scale (4 dp grid). Use these instead of numeric literals for
/// padding, gaps and margins.
abstract final class EripooSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// Corner radii.
abstract final class EripooRadii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;
}

/// Layout tokens shared by phone and tablet layouts.
abstract final class EripooLayout {
  /// Minimum interactive size (Material / Android accessibility guideline).
  static const double minTouchTarget = 48;

  /// Height of primary actions: larger than the minimum, for users less
  /// familiar with touch interfaces.
  static const double primaryActionHeight = 56;

  /// Horizontal page padding on phones (compact width).
  static const double gutterCompact = 16;

  /// Horizontal page padding on tablets (medium and expanded widths).
  static const double gutterMedium = 24;

  /// Maximum width of a reading column (≈ 60–75 characters).
  static const double maxReadableWidth = 640;

  /// Border widths.
  static const double borderThin = 1;
  static const double borderFocus = 2;
}
