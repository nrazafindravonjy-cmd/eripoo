import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../content/content_pack.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../hypotheses/presentation/research_forms.dart';
import '../../quest/presentation/content_widgets.dart';
import '../../quest/presentation/journey_providers.dart';
import '../../trash/application/trash_service.dart';
import '../../trash/presentation/trash_screen.dart';
import '../application/competitor_service.dart';
import 'tools_providers.dart';

String competitorKindLabel(AppLocalizations l10n, CompetitorKind kind) =>
    switch (kind) {
      CompetitorKind.direct => l10n.competitorKindDirect,
      CompetitorKind.indirect => l10n.competitorKindIndirect,
      CompetitorKind.alternative => l10n.competitorKindAlternative,
    };

/// The competitor analysis: what people already use instead of the project,
/// as the user saw or heard it.
class CompetitorsScreen extends ConsumerWidget {
  const CompetitorsScreen({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    String projectId, [
    Competitor? current,
  ]) async {
    final l10n = AppLocalizations.of(context);
    final kind = await showChoiceSheet<CompetitorKind>(
      context,
      title: l10n.competitorKindQuestion,
      options: [
        for (final k in CompetitorKind.values)
          (k, competitorKindLabel(l10n, k)),
      ],
    );
    if (kind == null || !context.mounted) return;
    final values = await showFieldsSheet(
      context,
      title: current == null ? l10n.competitorAdd : l10n.competitorEdit,
      fields: [
        FieldSpec(
          'name',
          l10n.competitorNameLabel,
          initial: current?.name,
          maxLength: CompetitorRules.maxNameLength,
        ),
        FieldSpec(
          'offer',
          l10n.competitorOfferLabel,
          initial: current?.offer,
          optional: true,
          maxLines: 3,
          maxLength: CompetitorRules.maxTextLength,
        ),
        FieldSpec(
          'price',
          l10n.competitorPriceLabel,
          initial: current?.priceMga?.toString(),
          optional: true,
          number: true,
        ),
        FieldSpec(
          'strengths',
          l10n.competitorStrengthsLabel,
          initial: current?.strengths,
          optional: true,
          maxLines: 3,
          maxLength: CompetitorRules.maxTextLength,
        ),
        FieldSpec(
          'weaknesses',
          l10n.competitorWeaknessesLabel,
          initial: current?.weaknesses,
          optional: true,
          maxLines: 3,
          maxLength: CompetitorRules.maxTextLength,
        ),
      ],
    );
    if (values == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final rawPrice = (values['price'] ?? '').replaceAll(RegExp(r'[\s.]'), '');
    final price = rawPrice.isEmpty ? null : int.tryParse(rawPrice);
    final service = ref.read(competitorServiceProvider);
    try {
      if (rawPrice.isNotEmpty && price == null) {
        throw const InvalidCompetitor();
      }
      if (current == null) {
        await service.add(
          projectId: projectId,
          name: values['name']!,
          kind: kind,
          offer: values['offer'],
          priceMga: price,
          strengths: values['strengths'],
          weaknesses: values['weaknesses'],
        );
      } else {
        await service.update(
          current.id,
          name: values['name']!,
          kind: kind,
          offer: values['offer'],
          priceMga: price,
          strengths: values['strengths'],
          weaknesses: values['weaknesses'],
        );
      }
    } on InvalidCompetitor {
      messenger.showSnackBar(SnackBar(content: Text(l10n.competitorInvalid)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tool = ref
        .watch(contentPackProvider)
        .tools
        .where((t) => t.kind == ToolKind.competitorAnalysis)
        .firstOrNull;
    final title = tool == null
        ? l10n.navTools
        : contentText(context, tool.title);
    final project = ref.watch(activeProjectProvider).value;
    if (project == null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: EripooMessageView(
          icon: Icons.work_outline,
          title: l10n.projectEmptyTitle,
          message: l10n.projectEmptyBody,
        ),
      );
    }
    final competitors = ref.watch(competitorsProvider(project.id));
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: competitors.when(
        loading: () => const EripooLoadingView(),
        error: (_, _) => const EripooErrorView(),
        data: (list) => ListView(
          padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
          children: [
            ReadableColumn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (tool != null)
                    for (final h in tool.help) ...[
                      Text(contentText(context, h)),
                      const SizedBox(height: EripooSpacing.sm),
                    ],
                  if (list.isEmpty) ...[
                    const SizedBox(height: EripooSpacing.md),
                    Text(l10n.competitorsEmpty),
                  ],
                  for (final c in list) ...[
                    const SizedBox(height: EripooSpacing.md),
                    _CompetitorCard(
                      competitor: c,
                      onEdit: () => _edit(context, ref, project.id, c),
                    ),
                  ],
                  const SizedBox(height: EripooSpacing.lg),
                  EripooButton(
                    label: l10n.competitorAdd,
                    icon: Icons.add,
                    onPressed: () => _edit(context, ref, project.id),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompetitorCard extends ConsumerWidget {
  const _CompetitorCard({required this.competitor, required this.onEdit});
  final Competitor competitor;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = competitor;
    return EripooCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.name, style: context.textStyles.titleSmall),
          Text(
            competitorKindLabel(l10n, c.kind),
            style: context.textStyles.labelMedium,
          ),
          if (c.offer != null) Text(c.offer!),
          if (c.priceMga != null)
            Text(l10n.competitorPrice(context.formatter.money(c.priceMga!))),
          if (c.strengths != null) ...[
            const SizedBox(height: EripooSpacing.xs),
            Text(
              l10n.competitorStrengthsLabel,
              style: context.textStyles.labelMedium,
            ),
            Text(c.strengths!),
          ],
          if (c.weaknesses != null) ...[
            const SizedBox(height: EripooSpacing.xs),
            Text(
              l10n.competitorWeaknessesLabel,
              style: context.textStyles.labelMedium,
            ),
            Text(c.weaknesses!),
          ],
          Wrap(
            spacing: EripooSpacing.sm,
            children: [
              EripooButton(
                label: l10n.competitorEdit,
                icon: Icons.edit_outlined,
                variant: EripooButtonVariant.tertiary,
                onPressed: onEdit,
              ),
              EripooButton(
                label: l10n.actionDelete,
                icon: Icons.delete_outline,
                variant: EripooButtonVariant.tertiary,
                onPressed: () =>
                    deleteWithUndo(context, ref, TrashKind.competitor, c.id),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
