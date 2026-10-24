import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../content/content_pack.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../conflicts/presentation/conflicts_screen.dart';
import '../../hypotheses/presentation/research_forms.dart';
import '../../hypotheses/presentation/research_providers.dart';
import '../../quest/presentation/content_widgets.dart';
import '../../quest/presentation/journey_providers.dart';
import '../../review/presentation/review_screen.dart';
import '../../tips/presentation/feature_tip.dart';
import '../../tools/application/tool_service.dart';
import '../../tools/presentation/tools_providers.dart';
import '../../trash/presentation/trash_screen.dart';
import '../data/project_repository.dart';
import '../domain/project.dart';
import 'project_card.dart';

/// The project: its sections (filled by the journey, editable, with a
/// light "before / now" history) and the way to test its ideas.
class ProjectScreen extends ConsumerWidget {
  const ProjectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final project = ref.watch(activeProjectProvider);
    return Scaffold(
      appBar: AppBar(title: Text(project.value?.title ?? l10n.navProject)),
      body: project.when(
        loading: () => const EripooLoadingView(),
        error: (_, _) => const EripooErrorView(),
        data: (project) => project == null
            ? EripooMessageView(
                icon: Icons.work_outline,
                title: l10n.projectEmptyTitle,
                message: l10n.projectEmptyBody,
              )
            : _ProjectBody(project),
      ),
    );
  }
}

class _ProjectBody extends ConsumerWidget {
  const _ProjectBody(this.project);
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pack = ref.watch(contentPackProvider);
    final sections = ref.watch(projectSectionsProvider(project.id)).value;
    final hypotheses = ref.watch(hypothesesProvider(project.id)).value;
    final notes = ref.watch(fieldNotesProvider(project.id)).value;
    final trashed = ref.watch(trashItemsProvider).value?.length ?? 0;
    final conflicts = ref.watch(pendingConflictsProvider).value?.length ?? 0;
    final toReview = ref.watch(reviewPointsProvider).value?.length ?? 0;
    final plan = ref.watch(journeyPlanProvider).value;
    final steps = plan == null
        ? 0
        : [?plan.diagnostic, ...plan.quests].fold(0, (n, q) => n + q.done);
    final unlocked = {
      for (final t in ref.watch(toolsProvider).value ?? const <ToolState>[])
        if (t.unlocked) t.tool.id,
    };
    // A section brought by a tool appears with the tool, or as soon as it
    // holds something: never hidden once written, never shown empty early.
    bool visible(SectionSchema schema) {
      if (schema.tool == null || unlocked.contains(schema.tool)) return true;
      final fields = sections?[schema.key]?.fields ?? const {};
      return fields.values.any((v) => (v?.toString() ?? '').trim().isNotEmpty);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
      children: [
        ReadableColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FeatureTip(
                id: 'project.card',
                message: l10n.tipProjectCard,
                child: ProjectCard(
                  project: project,
                  steps: steps,
                  currentQuest: switch (plan?.next) {
                    final next? => switch (pack.questOfStep(next.step.id)) {
                      final q? => contentText(context, q.title),
                      null => null,
                    },
                    null => null,
                  },
                ),
              ),
              const SizedBox(height: EripooSpacing.lg),
              Text(
                l10n.projectResearchTitle,
                style: context.textStyles.titleMedium,
              ),
              const SizedBox(height: EripooSpacing.sm),
              EripooNavRow(
                icon: Icons.science_outlined,
                label: l10n.projectHypothesesEntry(hypotheses?.length ?? 0),
                onTap: () => context.go(AppRoutes.hypotheses),
              ),
              EripooNavRow(
                icon: Icons.menu_book_outlined,
                label: l10n.projectFieldNotesEntry(notes?.count ?? 0),
                onTap: () => context.go(AppRoutes.fieldNotes),
              ),
              EripooNavRow(
                icon: Icons.calculate_outlined,
                label: l10n.projectFinanceEntry,
                onTap: () => context.go(AppRoutes.finances),
              ),
              EripooNavRow(
                icon: Icons.military_tech_outlined,
                label: l10n.badgesTitle,
                onTap: () => context.go(AppRoutes.badges),
              ),
              if (toReview > 0) ...[
                EripooNavRow(
                  icon: Icons.rule,
                  label: l10n.reviewEntry(toReview),
                  iconColor: context.colors.warning.base,
                  onTap: () => context.go(AppRoutes.review),
                ),
              ],
              if (conflicts > 0) ...[
                EripooNavRow(
                  icon: Icons.call_split,
                  label: l10n.projectConflictsEntry(conflicts),
                  onTap: () => context.go(AppRoutes.conflicts),
                ),
              ],
              if (trashed > 0) ...[
                EripooNavRow(
                  icon: Icons.delete_outline,
                  label: l10n.projectTrashEntry(trashed),
                  onTap: () => context.go(AppRoutes.trash),
                ),
              ],
              const SizedBox(height: EripooSpacing.xl),
              Text(
                l10n.projectSectionsTitle,
                style: context.textStyles.titleMedium,
              ),
              const SizedBox(height: EripooSpacing.sm),
              for (final schema in pack.sections.where(visible)) ...[
                ProjectSectionCard(
                  project: project,
                  schema: schema,
                  fields: sections?[schema.key]?.fields ?? const {},
                ),
                const SizedBox(height: EripooSpacing.md),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A project section: its fields, edit and history.
class ProjectSectionCard extends ConsumerWidget {
  const ProjectSectionCard({
    super.key,
    required this.project,
    required this.schema,
    required this.fields,
  });

  final Project project;
  final SectionSchema schema;
  final Map<String, Object?> fields;

  bool get _empty => schema.fields.every(
    (f) => (fields[f.key]?.toString() ?? '').trim().isEmpty,
  );

  Future<void> _edit(BuildContext context, WidgetRef ref) =>
      editProjectSection(context, ref, project.id, schema, fields);

  Future<void> _history(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final all = await ref.read(projectHistoryProvider(project.id).future);
    final revisions = all.where((r) => r.sectionKey == schema.key).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!context.mounted) return;
    await showFormSheet<void>(
      context,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.projectHistory, style: context.textStyles.titleLarge),
          const SizedBox(height: EripooSpacing.md),
          if (revisions.isEmpty) Text(l10n.projectHistoryEmpty),
          for (final r in revisions) ...[
            Text(
              l10n.projectHistoryEntry(
                contentText(
                  context,
                  schema.field(r.fieldKey)?.label ?? schema.title,
                ),
                context.formatter.dateShort(r.createdAt.toLocal()),
              ),
              style: context.textStyles.labelLarge,
            ),
            Text(
              l10n.projectHistoryBefore(
                r.previousValue ?? l10n.projectHistoryNoValue,
              ),
            ),
            Text(
              l10n.projectHistoryNow(r.newValue ?? l10n.projectHistoryNoValue),
            ),
            const Divider(),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return EripooCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            contentText(context, schema.title),
            style: context.textStyles.titleMedium,
          ),
          const SizedBox(height: EripooSpacing.xs),
          if (_empty)
            Text(l10n.projectSectionEmpty, style: context.textStyles.bodySmall)
          else
            for (final f in schema.fields)
              if ((fields[f.key]?.toString() ?? '').isNotEmpty) ...[
                Text(
                  contentText(context, f.label),
                  style: context.textStyles.labelMedium,
                ),
                Text(fields[f.key].toString()),
                const SizedBox(height: EripooSpacing.xs),
              ],
          Wrap(
            spacing: EripooSpacing.sm,
            children: [
              EripooButton(
                label: l10n.projectEditSection,
                icon: Icons.edit_outlined,
                variant: EripooButtonVariant.tertiary,
                onPressed: () => _edit(context, ref),
              ),
              EripooButton(
                label: l10n.projectHistory,
                icon: Icons.history,
                variant: EripooButtonVariant.tertiary,
                onPressed: () => _history(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Edits a project section's fields; each change made by hand is kept in
/// "before / now".
Future<void> editProjectSection(
  BuildContext context,
  WidgetRef ref,
  String projectId,
  SectionSchema schema,
  Map<String, Object?> fields,
) async {
  final l10n = AppLocalizations.of(context);
  final values = await showFieldsSheet(
    context,
    title: contentText(context, schema.title),
    fields: [
      for (final f in schema.fields)
        FieldSpec(
          f.key,
          contentText(context, f.label),
          initial: fields[f.key]?.toString(),
          maxLines: 4,
          maxLength: f.maxLength,
          optional: true,
        ),
    ],
    submitLabel: l10n.actionSave,
  );
  if (values == null) return;
  final changed = {
    for (final e in values.entries)
      if (e.value != (fields[e.key]?.toString() ?? '')) e.key,
  };
  if (changed.isEmpty) return;
  await ProjectRepository(ref.read(appDatabaseProvider)).saveSection(
    projectId: projectId,
    sectionKey: schema.key,
    fields: {
      ...fields,
      for (final e in values.entries) e.key: e.value.isEmpty ? null : e.value,
    },
    trackedFields: changed,
  );
}
