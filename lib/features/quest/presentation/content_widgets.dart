import 'package:flutter/material.dart';

import '../../../content/localized_text.dart';
import '../../../content/planner.dart';
import '../../../content/progress_state.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'journey_providers.dart';

/// Text of the content in the interface language (with fallback).
String contentText(BuildContext context, LocalizedText text) =>
    contentLocalizerOf(context)(text);

/// True if one of [texts] is shown in another language or not reviewed:
/// the screen then shows a discreet note (docs/PRODUCT_ARCHITECTURE.md §6.2).
bool needsReviewNote(BuildContext context, Iterable<LocalizedText> texts) {
  final localizer = contentLocalizerOf(context);
  return texts.any((t) {
    final r = localizer.resolve(t);
    return r.language != localizer.language ||
        r.status != ReviewStatus.reviewed;
  });
}

class ContentReviewNote extends StatelessWidget {
  const ContentReviewNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: EripooSpacing.sm),
      child: Row(
        children: [
          Icon(Icons.translate, size: 16, color: context.colors.textSecondary),
          const SizedBox(width: EripooSpacing.xs),
          Expanded(
            child: Text(
              AppLocalizations.of(context).contentReviewNote,
              style: context.textStyles.bodySmall?.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Short status of a planned step, in words (never colour only).
class StepStatusLabel extends StatelessWidget {
  const StepStatusLabel({super.key, required this.step});

  final PlannedStep step;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final (IconData icon, String label, Color color) = switch (step.status) {
      StepStatus.locked => (
        Icons.lock_outline,
        switch (step.lockReason) {
          LockReason.questLocked => l10n.questLockedQuest,
          LockReason.condition => l10n.stepLockedCondition,
          _ => l10n.stepLockedPrevious,
        },
        colors.textSecondary,
      ),
      StepStatus.available when step.resurfaced => (
        Icons.replay,
        l10n.stepStatusResurfaced,
        colors.brand.base,
      ),
      StepStatus.available => (
        Icons.play_circle_outline,
        l10n.stepStatusAvailable,
        colors.brand.base,
      ),
      StepStatus.inProgress => (
        Icons.timelapse,
        l10n.stepStatusInProgress,
        colors.brand.base,
      ),
      StepStatus.deferred => (
        Icons.schedule,
        l10n.stepStatusDeferred(
          step.deferredUntil == null
              ? ''
              : context.formatter.dateShort(step.deferredUntil!.toLocal()),
        ),
        colors.textSecondary,
      ),
      StepStatus.postponed => (
        Icons.bookmark_border,
        l10n.stepStatusPostponed,
        colors.textSecondary,
      ),
      StepStatus.fastTracked => (
        Icons.fast_forward,
        l10n.stepStatusFastTracked,
        colors.success.base,
      ),
      StepStatus.completed => (
        Icons.check_circle,
        l10n.stepStatusCompleted,
        colors.success.base,
      ),
    };
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: EripooSpacing.xs),
        Flexible(
          child: Text(
            label,
            style: context.textStyles.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
