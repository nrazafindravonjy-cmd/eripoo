import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../quest/presentation/journey_providers.dart';
import '../../trash/application/trash_service.dart';
import '../../trash/presentation/trash_screen.dart';
import '../domain/research.dart';
import 'research_forms.dart';
import 'research_providers.dart';

/// What the user saw and what people told them: written notes, photos as
/// evidence, pseudonyms only, no recording of other people.
class FieldNotesScreen extends ConsumerWidget {
  const FieldNotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final project = ref.watch(activeProjectProvider).value;
    if (project == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.fieldNotesTitle)),
        body: EripooMessageView(
          icon: Icons.work_outline,
          title: l10n.projectEmptyTitle,
          message: l10n.projectEmptyBody,
        ),
      );
    }
    final notes = ref.watch(fieldNotesProvider(project.id));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.fieldNotesTitle)),
      body: notes.when(
        loading: () => const EripooLoadingView(),
        error: (_, _) => const EripooErrorView(),
        data: (notes) => ListView(
          padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
          children: [
            ReadableColumn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (notes.count == 0) Text(l10n.fieldNotesEmpty),
                  const SizedBox(height: EripooSpacing.md),
                  Wrap(
                    spacing: EripooSpacing.sm,
                    runSpacing: EripooSpacing.sm,
                    children: [
                      EripooButton(
                        label: l10n.observationAdd,
                        icon: Icons.visibility_outlined,
                        onPressed: () =>
                            _addObservation(context, ref, project.id),
                      ),
                      EripooButton(
                        label: l10n.interviewAdd,
                        icon: Icons.forum_outlined,
                        variant: EripooButtonVariant.secondary,
                        onPressed: () =>
                            _addInterview(context, ref, project.id),
                      ),
                    ],
                  ),
                  if (notes.observations.isNotEmpty) ...[
                    const SizedBox(height: EripooSpacing.xl),
                    Text(
                      l10n.observationsTitle,
                      style: context.textStyles.titleMedium,
                    ),
                    for (final o in notes.observations) ...[
                      const SizedBox(height: EripooSpacing.sm),
                      EripooCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.formatter.date(o.observedAt.toLocal()),
                              style: context.textStyles.labelMedium,
                            ),
                            Text(o.description),
                            if (o.context != null)
                              Text(
                                o.context!,
                                style: context.textStyles.bodySmall,
                              ),
                            if (o.supposedProblem != null) ...[
                              const SizedBox(height: EripooSpacing.xs),
                              Text(
                                l10n.observationProblemLabel,
                                style: context.textStyles.labelMedium,
                              ),
                              Text(o.supposedProblem!),
                            ],
                            EvidenceList(
                              evidences: notes.evidences[o.id] ?? const [],
                              projectId: project.id,
                              subject: EvidenceSubject.observation,
                              subjectId: o.id,
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: EripooButton(
                                label: l10n.actionDelete,
                                icon: Icons.delete_outline,
                                variant: EripooButtonVariant.tertiary,
                                onPressed: () => deleteWithUndo(
                                  context,
                                  ref,
                                  TrashKind.observation,
                                  o.id,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                  if (notes.interviews.isNotEmpty) ...[
                    const SizedBox(height: EripooSpacing.xl),
                    Text(
                      l10n.interviewsTitle,
                      style: context.textStyles.titleMedium,
                    ),
                    for (final i in notes.interviews) ...[
                      const SizedBox(height: EripooSpacing.sm),
                      EripooCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              i.intervieweeAlias,
                              style: context.textStyles.titleSmall,
                            ),
                            Text(
                              context.formatter.date(i.heldAt.toLocal()),
                              style: context.textStyles.labelMedium,
                            ),
                            Text(i.notes),
                            if (i.conclusion != null) ...[
                              const SizedBox(height: EripooSpacing.xs),
                              Text(
                                l10n.interviewConclusionLabel,
                                style: context.textStyles.labelMedium,
                              ),
                              Text(i.conclusion!),
                            ],
                            EvidenceList(
                              evidences: notes.evidences[i.id] ?? const [],
                              projectId: project.id,
                              subject: EvidenceSubject.interview,
                              subjectId: i.id,
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: EripooButton(
                                label: l10n.actionDelete,
                                icon: Icons.delete_outline,
                                variant: EripooButtonVariant.tertiary,
                                onPressed: () => deleteWithUndo(
                                  context,
                                  ref,
                                  TrashKind.interview,
                                  i.id,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addObservation(
    BuildContext context,
    WidgetRef ref,
    String projectId,
  ) async {
    final l10n = AppLocalizations.of(context);
    final values = await showFieldsSheet(
      context,
      title: l10n.observationAdd,
      fields: [
        FieldSpec(
          'description',
          l10n.observationDescriptionLabel,
          maxLines: 5,
          maxLength: FieldNoteRules.maxNotesLength,
        ),
        FieldSpec(
          'context',
          l10n.observationContextLabel,
          optional: true,
          maxLength: FieldNoteRules.maxShortLength,
        ),
        FieldSpec(
          'problem',
          l10n.observationProblemLabel,
          optional: true,
          maxLines: 3,
          maxLength: FieldNoteRules.maxShortLength,
        ),
      ],
    );
    if (values == null || !context.mounted) return;
    await runGuarded(
      context,
      () => ref
          .read(researchServiceProvider)
          .addObservation(
            projectId: projectId,
            description: values['description']!,
            context: values['context'],
            supposedProblem: values['problem'],
          ),
    );
  }

  Future<void> _addInterview(
    BuildContext context,
    WidgetRef ref,
    String projectId,
  ) async {
    final l10n = AppLocalizations.of(context);
    final values = await showFieldsSheet(
      context,
      title: l10n.interviewAdd,
      note: l10n.interviewNoRecording,
      fields: [
        FieldSpec(
          'alias',
          l10n.interviewAliasLabel,
          helper: l10n.interviewAliasHelp,
          maxLength: FieldNoteRules.maxAliasLength,
        ),
        FieldSpec(
          'notes',
          l10n.interviewNotesLabel,
          maxLines: 6,
          maxLength: FieldNoteRules.maxNotesLength,
        ),
        FieldSpec(
          'conclusion',
          l10n.interviewConclusionLabel,
          optional: true,
          maxLines: 3,
          maxLength: FieldNoteRules.maxShortLength,
        ),
      ],
    );
    if (values == null || !context.mounted) return;
    await runGuarded(
      context,
      () => ref
          .read(researchServiceProvider)
          .addInterview(
            projectId: projectId,
            alias: values['alias']!,
            notes: values['notes']!,
            conclusion: values['conclusion'],
          ),
    );
  }
}
