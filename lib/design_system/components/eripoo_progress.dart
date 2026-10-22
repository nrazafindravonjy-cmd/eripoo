import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../theme/eripoo_theme.dart';
import '../theme/format_context.dart';
import '../tokens/eripoo_dimens.dart';
import '../tokens/eripoo_motion.dart';

/// Numeric progress, e.g. "4 / 12", with a bar. Measures work done, never a
/// chance of success.
class EripooProgress extends StatelessWidget {
  const EripooProgress({
    super.key,
    required this.done,
    required this.total,
    this.label,
  }) : assert(total > 0),
       assert(done >= 0 && done <= total);

  final int done;
  final int total;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final format = context.formatter;
    final motion = EripooMotion.of(context);
    final text = context.textStyles;
    final semanticsValue = l10n.progressValue(
      format.integer(done),
      format.integer(total),
    );

    return Semantics(
      label: label,
      value: semanticsValue,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (label != null)
                Expanded(child: Text(label!, style: text.titleSmall)),
              Text(format.fraction(done, total), style: text.labelLarge),
            ],
          ),
          const SizedBox(height: EripooSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(EripooRadii.pill),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: done / total),
              duration: motion.slow,
              curve: motion.standard,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: EripooSpacing.sm,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A sequence of named stages (e.g. project maturity) with the current one
/// highlighted. Only the current stage name is shown, so it fits phones.
class EripooStepTrack extends StatelessWidget {
  const EripooStepTrack({
    super.key,
    required this.steps,
    required this.currentIndex,
  });

  final List<String> steps;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    assert(steps.length > 1, 'A step track needs at least two steps.');
    assert(currentIndex >= 0 && currentIndex < steps.length);
    final colors = context.colors;
    final format = context.formatter;
    final l10n = AppLocalizations.of(context);
    const dot = EripooSpacing.md;

    return Semantics(
      label: l10n.stepTrackValue(
        format.integer(currentIndex + 1),
        format.integer(steps.length),
        steps[currentIndex],
      ),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0)
                  Expanded(
                    child: Container(
                      height: EripooLayout.borderFocus,
                      color: i <= currentIndex
                          ? colors.brand.base
                          : colors.borderStrong,
                    ),
                  ),
                Container(
                  width: i == currentIndex ? dot * 1.5 : dot,
                  height: i == currentIndex ? dot * 1.5 : dot,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i <= currentIndex
                        ? colors.brand.base
                        : colors.surface,
                    border: Border.all(
                      color: i <= currentIndex
                          ? colors.brand.base
                          : colors.borderStrong,
                      width: EripooLayout.borderFocus,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: EripooSpacing.sm),
          Text(steps[currentIndex], style: context.textStyles.titleSmall),
        ],
      ),
    );
  }
}
