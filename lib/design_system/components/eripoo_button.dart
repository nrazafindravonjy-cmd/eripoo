import 'package:flutter/material.dart';

import '../theme/eripoo_theme.dart';
import '../tokens/eripoo_dimens.dart';

enum EripooButtonVariant {
  /// The main action of a screen (at most one per screen).
  primary,

  /// Alternative actions.
  secondary,

  /// Low-emphasis actions (links, "later").
  tertiary,

  /// Irreversible actions (delete).
  danger,
}

/// Eripoo button. Labels come from ARB files or content, never literals.
class EripooButton extends StatelessWidget {
  const EripooButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = EripooButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.expand = false,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final EripooButtonVariant variant;
  final IconData? icon;

  /// Shows a progress indicator and ignores presses, keeping the label for
  /// screen readers.
  final bool isLoading;

  /// Takes the full available width (typical for the primary action on
  /// phones).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // While loading, keep the enabled appearance (a greyed-out label would be
    // hard to read) but ignore presses.
    final VoidCallback? callback = isLoading
        ? (onPressed == null ? null : () {})
        : onPressed;
    final Widget content = isLoading
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: EripooSpacing.xl,
                child: CircularProgressIndicator(
                  strokeWidth: EripooLayout.borderFocus,
                  color: _contentColor(context),
                ),
              ),
              const SizedBox(width: EripooSpacing.md),
              Flexible(child: Text(label)),
            ],
          )
        : Text(label, textAlign: TextAlign.center);

    final Widget button = switch (variant) {
      EripooButtonVariant.primary when icon != null && !isLoading =>
        FilledButton.icon(
          onPressed: callback,
          icon: Icon(icon),
          label: content,
        ),
      EripooButtonVariant.primary => FilledButton(
        onPressed: callback,
        child: content,
      ),
      EripooButtonVariant.secondary when icon != null && !isLoading =>
        OutlinedButton.icon(
          onPressed: callback,
          icon: Icon(icon),
          label: content,
        ),
      EripooButtonVariant.secondary => OutlinedButton(
        onPressed: callback,
        child: content,
      ),
      EripooButtonVariant.tertiary when icon != null && !isLoading =>
        TextButton.icon(onPressed: callback, icon: Icon(icon), label: content),
      EripooButtonVariant.tertiary => TextButton(
        onPressed: callback,
        child: content,
      ),
      // Outlined, so yellow stays the one dominant element of a screen.
      EripooButtonVariant.danger => OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.danger.base,
          side: BorderSide(color: colors.danger.base),
        ),
        onPressed: callback,
        child: content,
      ),
    };

    final semantic = Semantics(
      button: true,
      enabled: onPressed != null && !isLoading,
      label: label,
      excludeSemantics: true,
      child: IgnorePointer(ignoring: isLoading, child: button),
    );
    return expand
        ? SizedBox(width: double.infinity, child: semantic)
        : semantic;
  }

  Color _contentColor(BuildContext context) {
    final colors = context.colors;
    return switch (variant) {
      EripooButtonVariant.primary => colors.brand.onBase,
      EripooButtonVariant.danger => colors.danger.base,
      EripooButtonVariant.secondary => colors.textPrimary,
      EripooButtonVariant.tertiary => colors.textPrimary,
    };
  }
}
