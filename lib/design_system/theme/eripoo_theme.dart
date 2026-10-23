import 'package:flutter/material.dart';

import '../tokens/eripoo_colors.dart';
import '../tokens/eripoo_dimens.dart';
import '../tokens/eripoo_typography.dart';

/// Builds the Material theme from Eripoo tokens, for light or dark mode.
///
/// Material widgets are themed here so that screens never pass colours,
/// radii or text styles by hand.
abstract final class EripooTheme {
  static ThemeData light() => _build(Brightness.light, EripooColors.light);
  static ThemeData dark() => _build(Brightness.dark, EripooColors.dark);

  static ThemeData _build(Brightness brightness, EripooColors c) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.brand.base,
      onPrimary: c.brand.onBase,
      primaryContainer: c.brand.container,
      onPrimaryContainer: c.brand.onContainer,
      secondary: c.accent.base,
      onSecondary: c.accent.onBase,
      secondaryContainer: c.accent.container,
      onSecondaryContainer: c.accent.onContainer,
      tertiary: c.info.base,
      onTertiary: c.info.onBase,
      tertiaryContainer: c.info.container,
      onTertiaryContainer: c.info.onContainer,
      error: c.danger.base,
      onError: c.danger.onBase,
      errorContainer: c.danger.container,
      onErrorContainer: c.danger.onContainer,
      surface: c.surface,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      surfaceContainerLowest: c.surface,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceMuted,
      surfaceContainerHighest: c.surfaceMuted,
      outline: c.borderStrong,
      outlineVariant: c.border,
      scrim: c.scrim,
      shadow: c.scrim,
      surfaceTint: Colors.transparent,
      inverseSurface: c.textPrimary,
      onInverseSurface: c.surface,
      inversePrimary: c.brand.container,
    );
    // Merge the Eripoo scale with Material typography so every style has
    // the platform font resolved, then use the merged styles everywhere.
    final text = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      textTheme: EripooTypography.textTheme(c.textPrimary, c.textSecondary),
    ).textTheme;

    final actionShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(EripooRadii.md),
    );
    const actionSize = Size(
      EripooLayout.minTouchTarget,
      EripooLayout.primaryActionHeight,
    );
    const actionPadding = EdgeInsets.symmetric(horizontal: EripooSpacing.xl);

    OutlineInputBorder inputBorder(Color color, double width) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(EripooRadii.md),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: text,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      dividerTheme: DividerThemeData(
        color: c.border,
        thickness: EripooLayout.borderThin,
        space: EripooSpacing.lg,
      ),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: actionSize,
          padding: actionPadding,
          shape: actionShape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: actionSize,
          padding: actionPadding,
          shape: actionShape,
          textStyle: text.labelLarge,
          foregroundColor: c.textPrimary,
          side: BorderSide(color: c.borderStrong),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(
            EripooLayout.minTouchTarget,
            EripooLayout.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: EripooSpacing.lg),
          shape: actionShape,
          textStyle: text.labelLarge,
          foregroundColor: c.brand.base,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(EripooLayout.minTouchTarget),
          foregroundColor: c.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EripooRadii.lg),
          side: BorderSide(color: c.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: EripooSpacing.lg,
          vertical: EripooSpacing.lg,
        ),
        labelStyle: text.bodyLarge?.copyWith(color: c.textSecondary),
        hintStyle: text.bodyLarge?.copyWith(color: c.textSecondary),
        helperStyle: text.bodySmall,
        errorStyle: text.bodySmall?.copyWith(color: c.danger.base),
        border: inputBorder(c.borderStrong, EripooLayout.borderThin),
        enabledBorder: inputBorder(c.borderStrong, EripooLayout.borderThin),
        focusedBorder: inputBorder(c.brand.base, EripooLayout.borderFocus),
        errorBorder: inputBorder(c.danger.base, EripooLayout.borderThin),
        focusedErrorBorder: inputBorder(
          c.danger.base,
          EripooLayout.borderFocus,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.brand.base,
        linearTrackColor: c.brand.container,
        circularTrackColor: c.brand.container,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.brand.container,
        elevation: 0,
        // Navigation labels are short single words; 12 sp keeps them on
        // one line at 360 dp (tested).
        labelTextStyle: WidgetStatePropertyAll(
          text.labelSmall?.copyWith(color: c.textPrimary),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? c.brand.onContainer
                : c.textSecondary,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.brand.container,
        selectedIconTheme: IconThemeData(color: c.brand.onContainer),
        unselectedIconTheme: IconThemeData(color: c.textSecondary),
        selectedLabelTextStyle: text.labelMedium,
        unselectedLabelTextStyle: text.labelMedium?.copyWith(
          color: c.textSecondary,
        ),
        labelType: NavigationRailLabelType.all,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EripooRadii.xl),
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyLarge,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: c.scrim,
        showDragHandle: true,
        dragHandleColor: c.borderStrong,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(EripooRadii.xl),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.textPrimary,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.surface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EripooRadii.md),
        ),
      ),
      extensions: [c],
    );
  }
}

/// Short access to Eripoo tokens from widgets.
extension EripooThemeContext on BuildContext {
  EripooColors get colors => Theme.of(this).extension<EripooColors>()!;
  TextTheme get textStyles => Theme.of(this).textTheme;
}
