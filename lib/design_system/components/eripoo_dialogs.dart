import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../theme/eripoo_theme.dart';
import '../tokens/eripoo_dimens.dart';
import 'eripoo_button.dart';

/// Asks the user to confirm an action. Resolves to true only on explicit
/// confirmation (dismissing counts as cancel).
Future<bool> showEripooConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final l10n = AppLocalizations.of(context);
  final result = await showDialog<bool>(
    context: context,
    barrierColor: context.colors.scrim,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actionsPadding: const EdgeInsets.fromLTRB(
        EripooSpacing.xl,
        0,
        EripooSpacing.xl,
        EripooSpacing.xl,
      ),
      actions: [
        EripooButton(
          label: cancelLabel ?? l10n.actionCancel,
          variant: EripooButtonVariant.tertiary,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        EripooButton(
          label: confirmLabel,
          variant: destructive
              ? EripooButtonVariant.danger
              : EripooButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Opens a modal bottom sheet with Eripoo spacing. The content scrolls when
/// it is taller than the screen (large font sizes).
Future<T?> showEripooSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        EripooSpacing.lg,
        0,
        EripooSpacing.lg,
        EripooSpacing.xl,
      ),
      child: builder(context),
    ),
  );
}
