import 'package:flutter/material.dart';

import '../shapes/eripoo_shapes.dart';
import '../theme/eripoo_theme.dart';
import '../tokens/eripoo_dimens.dart';
import 'eripoo_done_mark.dart';
import 'eripoo_headline.dart';
import 'eripoo_mascot.dart';

/// A yellow sheet rising from the bottom when something big is finished
/// (a quest): the Eripoo mark appears, a serif title, one line and one
/// action. Shown once by the caller; still with reduced motion.
Future<void> showEripooCelebration(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
}) {
  final c = context.colors;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.brand.base,
    showDragHandle: false,
    isScrollControlled: true,
    shape: const EripooCutBorder(radius: EripooRadii.xl, cut: 0),
    builder: (context) {
      final t = context.textStyles;
      final ink = c.brand.onBase;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(EripooSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: EripooSpacing.lg),
              if (EripooMascotScope.enabledOf(context))
                const EripooMascot(
                  mood: EripooMood.happy,
                  height: 150,
                  hop: true,
                )
              else
                EripooDoneMark(size: 72, color: ink),
              const SizedBox(height: EripooSpacing.xl),
              DefaultTextStyle.merge(
                textAlign: TextAlign.center,
                child: EripooHeadline(
                  title,
                  style: t.headlineMedium?.copyWith(color: ink),
                  // Yellow italics would vanish on the yellow sheet.
                  emphasisColor: ink,
                ),
              ),
              const SizedBox(height: EripooSpacing.sm),
              Text(
                message,
                style: t.bodyLarge?.copyWith(color: ink),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: EripooSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: ink,
                    foregroundColor: c.textPrimary,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(actionLabel),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
