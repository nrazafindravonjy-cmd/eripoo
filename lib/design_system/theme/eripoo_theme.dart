import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shapes/eripoo_shapes.dart';
import '../tokens/eripoo_colors.dart';
import '../tokens/eripoo_dimens.dart';
import '../tokens/eripoo_typography.dart';

/// Builds the Material theme from Eripoo tokens (dark only).
///
/// Material widgets are themed here so that screens never pass colours,
/// radii or text styles by hand.
abstract final class EripooTheme {
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

    // Signature shape (the logo's cut corner) on every button and card.
    const actionShape = EripooCutBorder(radius: EripooRadii.lg, cut: 14);
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
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: c.background,
        ),
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
          textStyle: text.labelLarge?.copyWith(
            decoration: TextDecoration.underline,
            decorationColor: c.textSecondary,
          ),
          foregroundColor: c.textPrimary,
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
        shape: const EripooCutBorder(radius: EripooRadii.xl, cut: 22),
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
        backgroundColor: c.background,
        // The selected icon sits on an Eripoo mark (not the generic pill).
        indicatorColor: c.brand.container,
        indicatorShape: const EripooNavMarkBorder(),
        elevation: 0,
        // Navigation labels are short single words; 12 sp keeps them on
        // one line at 360 dp (tested).
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? text.labelSmall?.copyWith(color: c.textPrimary)
              : text.labelSmall?.copyWith(
                  color: c.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
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
        backgroundColor: c.background,
        indicatorColor: c.brand.container,
        indicatorShape: const EripooNavMarkBorder(),
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
        shape: const EripooCutBorder(radius: EripooRadii.xl, cut: 26),
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
        // Confirmations take the shape of the logo's speech bubble.
        backgroundColor: c.textPrimary,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.background),
        actionTextColor: c.background,
        shape: const EripooCutBorder(radius: EripooRadii.md, cut: 12),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: EripooPageTransitionsBuilder(),
          TargetPlatform.iOS: EripooPageTransitionsBuilder(),
        },
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

/// Pages slide in along the diagonal of the logo, with a fade; nothing
/// moves when the user asks for reduced motion.
class EripooPageTransitionsBuilder extends PageTransitionsBuilder {
  const EripooPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0.08, 0.05),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
