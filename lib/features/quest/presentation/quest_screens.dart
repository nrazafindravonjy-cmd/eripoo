import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../content/content_pack.dart';
import '../../../content/planner.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../tips/presentation/feature_tip.dart';
import 'content_widgets.dart';
import 'journey_providers.dart';

/// "Ma quête": the journey quests with their progress.
class QuestListScreen extends ConsumerWidget {
  const QuestListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final plan = ref.watch(journeyPlanProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navQuest)),
      body: plan.when(
        loading: () => const EripooLoadingView(),
        error: (_, _) => const EripooErrorView(),
        data: (plan) {
          final quests = plan.quests
              .where((q) => q.available || !q.quest.hideWhenLocked)
              .toList();
          // The journey reads as a path: one mark per quest.
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
            children: [
              ReadableColumn(
                child: FeatureTip(
                  id: 'quest.path',
                  message: AppLocalizations.of(context).tipQuestPath,
                  child: const SizedBox.shrink(),
                ),
              ),
              for (final (i, q) in quests.indexed)
                ReadableColumn(
                  child: EripooPathItem(
                    state: !q.available
                        ? EripooPathState.locked
                        : q.done >= q.total
                        ? EripooPathState.done
                        : EripooPathState.current,
                    isFirst: i == 0,
                    isLast: i == quests.length - 1,
                    child: _QuestCard(quest: q),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _QuestCard extends StatelessWidget {
  const _QuestCard({required this.quest});

  final PlannedQuest quest;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = contentText(context, quest.quest.title);
    return EripooCard(
      semanticLabel: title,
      onTap: () => context.go(AppRoutes.questDetail(quest.quest.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.textStyles.titleMedium),
          const SizedBox(height: EripooSpacing.xs),
          Text(
            contentText(context, quest.quest.summary),
            style: context.textStyles.bodyMedium,
          ),
          const SizedBox(height: EripooSpacing.md),
          if (quest.available)
            EripooProgress(done: quest.done, total: quest.total)
          else
            Row(
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 18,
                  color: context.colors.textSecondary,
                ),
                const SizedBox(width: EripooSpacing.xs),
                Expanded(
                  child: Text(
                    l10n.questLockedQuest,
                    style: context.textStyles.bodySmall,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// One quest: its steps and their status.
class QuestDetailScreen extends ConsumerWidget {
  const QuestDetailScreen({super.key, required this.questId});

  final String questId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(journeyPlanProvider);
    return plan.when(
      loading: () => const Scaffold(body: EripooLoadingView()),
      error: (_, _) => const Scaffold(body: EripooErrorView()),
      data: (plan) {
        final quest = plan.quests.where((q) => q.quest.id == questId);
        if (quest.isEmpty) return const Scaffold(body: EripooErrorView());
        final q = quest.single;
        return Scaffold(
          // The title is the headline below (not repeated in the bar).
          appBar: AppBar(),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
            children: [
              // Context first (yellow italics), then the goal (large serif).
              if (plan.quests
                      .where((x) => x.available || !x.quest.hideWhenLocked)
                      .toList()
                      .indexOf(q)
                  case final i when i >= 0)
                ReadableColumn(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: EripooSpacing.lg),
                    child: EripooHeadline(
                      '*${AppLocalizations.of(context).questNumber(i + 1)}*\n'
                      '${contentText(context, q.quest.title)}',
                    ),
                  ),
                ),
              // What to expect, read before starting.
              ReadableColumn(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: EripooSpacing.lg),
                  child: EripooMetrics(
                    items: [
                      (
                        AppLocalizations.of(context).metricSteps,
                        '${q.done} / ${q.total}',
                      ),
                      (
                        AppLocalizations.of(context).metricStage,
                        _stageLabel(context, q.quest.maturity),
                      ),
                      (
                        AppLocalizations.of(context).metricMissions,
                        '${q.steps.fold(0, (n, s) => n + s.step.missionIds.length)}',
                      ),
                    ],
                  ),
                ),
              ),
              for (final (i, s) in q.steps.indexed)
                ReadableColumn(
                  child: EripooPathItem(
                    state: s.isDone
                        ? EripooPathState.done
                        : s.canStart
                        ? EripooPathState.current
                        : EripooPathState.locked,
                    isFirst: i == 0,
                    isLast: i == q.steps.length - 1,
                    child: _StepTile(step: s),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

String _stageLabel(BuildContext context, String maturity) {
  final l10n = AppLocalizations.of(context);
  return switch (maturity) {
    'exploration' => l10n.maturityExploration,
    'validation' => l10n.maturityValidation,
    'construction' => l10n.maturityConstruction,
    'preparation' => l10n.maturityPreparation,
    'launch' => l10n.maturityLaunch,
    _ => maturity,
  };
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step});

  final PlannedStep step;

  @override
  Widget build(BuildContext context) {
    final title = contentText(context, step.step.title);
    // Done steps stay readable; locked ones explain what to do before.
    final open = step.canStart || step.isDone;
    return EripooCard(
      semanticLabel: title,
      onTap: open ? () => context.push(AppRoutes.step(step.step.id)) : null,
      child: Row(
        children: [
          // A small organic form per kind of step (learn, act, reflect…).
          EripooOrganicShape(size: 40, seed: step.step.type.index * 3 + 1),
          const SizedBox(width: EripooSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _typeLabel(context, step.step.type),
                  style: context.textStyles.labelSmall,
                ),
                Text(title, style: context.textStyles.titleSmall),
                const SizedBox(height: EripooSpacing.xs),
                StepStatusLabel(step: step),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _typeLabel(BuildContext context, StepType type) {
  final l10n = AppLocalizations.of(context);
  return switch (type) {
    StepType.learn => l10n.stepTypeLearn,
    StepType.reflect => l10n.stepTypeReflect,
    StepType.act => l10n.stepTypeAct,
    StepType.checkpoint => l10n.stepTypeCheckpoint,
    StepType.tool => l10n.stepTypeTool,
  };
}
