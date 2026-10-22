import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../content/planner.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
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
        data: (plan) => ListView(
          padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
          children: [
            for (final q in plan.quests)
              ReadableColumn(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: EripooSpacing.md),
                  child: _QuestCard(quest: q),
                ),
              ),
          ],
        ),
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
          appBar: AppBar(title: Text(contentText(context, q.quest.title))),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
            children: [
              ReadableColumn(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: EripooSpacing.lg),
                  child: EripooProgress(done: q.done, total: q.total),
                ),
              ),
              for (final s in q.steps)
                ReadableColumn(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: EripooSpacing.sm),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.textStyles.titleSmall),
          const SizedBox(height: EripooSpacing.xs),
          StepStatusLabel(step: step),
        ],
      ),
    );
  }
}
