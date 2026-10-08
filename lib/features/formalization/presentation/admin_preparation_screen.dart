import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../content/content_pack.dart';
import '../../../content/formalization.dart';
import '../../../content/localized_text.dart';
import '../../../core/format/eripoo_formatter.dart';
import '../../../core/time/clock.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../documents/presentation/document_model.dart';
import '../../documents/presentation/pdf_export.dart';
import '../../finance/domain/finance_math.dart';
import '../../hypotheses/presentation/research_forms.dart';
import '../../hypotheses/presentation/research_providers.dart';
import '../../project/presentation/project_screen.dart';
import '../../quest/presentation/content_widgets.dart';
import '../../quest/presentation/journey_providers.dart';
import '../application/preparation_service.dart';
import '../domain/creation_fees.dart';

/// Time used to tell whether the information may be out of date.
final clockProvider = Provider<Clock>((ref) => systemClock);

final preparationServiceProvider = Provider<PreparationService>(
  (ref) => PreparationService(ref.watch(appDatabaseProvider)),
);

/// "Source: EDBM — Création de société, Version 28 (p. 2, Frais)".
String sourceLine(
  AppLocalizations l10n,
  FormalizationContent content,
  SourceRef ref,
) {
  final s = content.source(ref.sourceId)!;
  final name = s.version == null
      ? '${s.publisher} — ${s.title}'
      : '${s.publisher} — ${s.title}, ${s.version}';
  return l10n.formalizationSource(name, ref.where);
}

String feeLineLabel(AppLocalizations l10n, FeeLineKind kind) =>
    l10n.feeLine(kind.name);

/// The administrative preparation (CLAUDE.md §19): explains, asks, collects
/// and prepares, says where to go; never claims to do the procedure. Every
/// rule shown carries its official source and its date.
class AdminPreparationScreen extends ConsumerWidget {
  const AdminPreparationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pack = ref.watch(contentPackProvider);
    final tool = pack.tools
        .where((t) => t.kind == ToolKind.adminPreparation)
        .firstOrNull;
    final content = pack.formalization;
    final project = ref.watch(activeProjectProvider).value;
    final title = tool == null
        ? l10n.navTools
        : contentText(context, tool.title);
    if (content == null || project == null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: EripooMessageView(
          icon: Icons.account_balance_outlined,
          title: title,
          message: content == null
              ? l10n.formalizationNone
              : l10n.projectEmptyBody,
        ),
      );
    }
    final sections = ref.watch(projectSectionsProvider(project.id)).value;
    final prep = Preparation.fromFields(
      sections?[PreparationService.sectionKey]?.fields ?? const {},
    );
    final schema = pack.section('formalization');
    final outdated = ref.watch(clockProvider)().isAfter(content.reviewAfter);
    final f = context.formatter;
    final consulted = content.sources
        .map((s) => s.consulted)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
        children: [
          ReadableColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EripooCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline),
                      const SizedBox(width: EripooSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.formalizationNotice(f.date(consulted))),
                            if (!content.legallyReviewed)
                              Text(
                                l10n.formalizationNotReviewed,
                                style: context.textStyles.labelLarge,
                              ),
                            if (outdated)
                              Text(
                                l10n.formalizationOutdated,
                                style: context.textStyles.labelLarge,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (schema != null) ...[
                  const SizedBox(height: EripooSpacing.lg),
                  ProjectSectionCard(
                    project: project,
                    schema: schema,
                    fields: sections?[schema.key]?.fields ?? const {},
                  ),
                ],
                for (final topic in content.topics) ...[
                  const SizedBox(height: EripooSpacing.lg),
                  _TopicCard(content: content, topic: topic),
                ],
                const SizedBox(height: EripooSpacing.xl),
                _Checklist(projectId: project.id, content: content, prep: prep),
                if (content.fees != null) ...[
                  const SizedBox(height: EripooSpacing.xl),
                  _FeeEstimate(
                    projectId: project.id,
                    fees: content.fees!,
                    prep: prep,
                  ),
                ],
                const SizedBox(height: EripooSpacing.xl),
                Text(
                  l10n.formalizationSourcesTitle,
                  style: context.textStyles.titleMedium,
                ),
                for (final s in content.sources) ...[
                  const SizedBox(height: EripooSpacing.sm),
                  Text(
                    l10n.formalizationSourceEntry(
                      s.version == null
                          ? '${s.publisher} — ${s.title}'
                          : '${s.publisher} — ${s.title}, ${s.version}',
                      f.date(s.consulted),
                    ),
                    style: context.textStyles.labelMedium,
                  ),
                  SelectableText(s.url, style: context.textStyles.bodySmall),
                ],
                const SizedBox(height: EripooSpacing.xl),
                EripooButton(
                  label: l10n.exportPdf,
                  icon: Icons.picture_as_pdf_outlined,
                  onPressed: () => exportPdf(
                    context,
                    ref,
                    kind: PdfKind.dossier,
                    title: title,
                    parts: preparationParts(
                      l10n: l10n,
                      formatter: f,
                      content: content,
                      text: (t) => contentText(context, t),
                      schema: schema,
                      fields: sections?[schema?.key]?.fields ?? const {},
                      prep: prep,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.content, required this.topic});

  final FormalizationContent content;
  final FormalizationTopic topic;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EripooCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            contentText(context, topic.title),
            style: context.textStyles.titleMedium,
          ),
          for (final fact in topic.facts) ...[
            const SizedBox(height: EripooSpacing.sm),
            Text(contentText(context, fact.text)),
            Text(
              sourceLine(l10n, content, fact.ref),
              style: context.textStyles.labelSmall,
            ),
          ],
          for (final advice in topic.advice) ...[
            const SizedBox(height: EripooSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline, size: 18),
                const SizedBox(width: EripooSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.formalizationAdvice(contentText(context, advice)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Checklist extends ConsumerWidget {
  const _Checklist({
    required this.projectId,
    required this.content,
    required this.prep,
  });

  final String projectId;
  final FormalizationContent content;
  final Preparation prep;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final items = content.checklist;
    final done = items.where((i) => prep.ready.contains(i.id)).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.formalizationChecklistTitle,
          style: context.textStyles.titleMedium,
        ),
        Text(
          l10n.formalizationChecklistProgress(
            context.formatter.fraction(done, items.length),
          ),
          style: context.textStyles.labelLarge,
        ),
        for (final item in items)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: prep.ready.contains(item.id),
            title: Text(contentText(context, item.text)),
            subtitle: Text(
              [
                if (item.when != null) contentText(context, item.when!),
                sourceLine(l10n, content, item.ref),
              ].join('\n'),
            ),
            onChanged: (v) => ref
                .read(preparationServiceProvider)
                .setReady(projectId, item.id, v ?? false),
          ),
      ],
    );
  }
}

class _FeeEstimate extends ConsumerStatefulWidget {
  const _FeeEstimate({
    required this.projectId,
    required this.fees,
    required this.prep,
  });

  final String projectId;
  final FeeSchedule fees;
  final Preparation prep;

  @override
  ConsumerState<_FeeEstimate> createState() => _FeeEstimateState();
}

class _FeeEstimateState extends ConsumerState<_FeeEstimate> {
  late final _capital = TextEditingController(
    text: widget.prep.capitalMga?.toString() ?? '',
  );
  late final _rent = TextEditingController(
    text: widget.prep.monthlyRentMga?.toString() ?? '',
  );
  late final _months = TextEditingController(
    text: widget.prep.leaseMonths?.toString() ?? '',
  );
  late String? _taxId = widget.prep.taxId;
  late bool _represented = widget.prep.represented;

  @override
  void dispose() {
    _capital.dispose();
    _rent.dispose();
    _months.dispose();
    super.dispose();
  }

  int? _read(TextEditingController c) =>
      c.text.trim().isEmpty ? null : parseAmount(c.text);

  bool _invalid(TextEditingController c) =>
      c.text.trim().isNotEmpty && parseAmount(c.text) == null;

  Preparation get _current => widget.prep.copyWith(
    capitalMga: () => _read(_capital),
    taxId: () => _taxId,
    monthlyRentMga: () => _read(_rent),
    leaseMonths: () => _read(_months),
    represented: _represented,
  );

  Future<void> _chooseActivity() async {
    final chosen = await showChoiceSheet<String>(
      context,
      title: AppLocalizations.of(context).feesActivity,
      options: [
        for (final t in widget.fees.syntheticTax)
          (t.id, contentText(context, t.label)),
      ],
    );
    if (chosen != null) setState(() => _taxId = chosen);
  }

  Future<void> _keep() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(preparationServiceProvider).save(widget.projectId, _current);
    messenger.showSnackBar(SnackBar(content: Text(l10n.feesKept)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final f = context.formatter;
    final tax = widget.fees.syntheticTax
        .where((t) => t.id == _taxId)
        .firstOrNull;
    FeeEstimate? estimate;
    var refused = false;
    final input = _current.feeInput;
    if (input != null) {
      try {
        estimate = estimateCreationFees(widget.fees, input);
      } on InvalidFeeInput {
        refused = true;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.feesTitle, style: context.textStyles.titleMedium),
        const SizedBox(height: EripooSpacing.sm),
        EripooTextField(
          label: l10n.feesCapital,
          controller: _capital,
          keyboardType: TextInputType.number,
          errorText: _invalid(_capital) ? l10n.calcInvalid : null,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: EripooSpacing.sm),
        EripooButton(
          label: tax == null
              ? l10n.feesActivityChoose
              : contentText(context, tax.label),
          icon: Icons.work_outline,
          variant: EripooButtonVariant.secondary,
          onPressed: _chooseActivity,
        ),
        const SizedBox(height: EripooSpacing.sm),
        EripooTextField(
          label: l10n.feesRent,
          controller: _rent,
          isOptional: true,
          keyboardType: TextInputType.number,
          errorText: _invalid(_rent) ? l10n.calcInvalid : null,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: EripooSpacing.sm),
        EripooTextField(
          label: l10n.feesMonths,
          controller: _months,
          isOptional: true,
          keyboardType: TextInputType.number,
          errorText: _invalid(_months) ? l10n.calcInvalid : null,
          onChanged: (_) => setState(() {}),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _represented,
          title: Text(l10n.feesRepresented),
          onChanged: (v) => setState(() => _represented = v),
        ),
        Semantics(
          liveRegion: true,
          child: EripooCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (estimate == null)
                  Text(refused ? l10n.feesRefused : l10n.feesFillIn)
                else ...[
                  for (final line in estimate.lines)
                    Row(
                      children: [
                        Expanded(child: Text(feeLineLabel(l10n, line.kind))),
                        Text(f.money(line.amountMga)),
                      ],
                    ),
                  const Divider(),
                  Text(
                    l10n.feesTotal(f.money(estimate.totalMga)),
                    style: context.textStyles.titleSmall,
                  ),
                ],
                const SizedBox(height: EripooSpacing.sm),
                Text(l10n.feesNote, style: context.textStyles.bodySmall),
              ],
            ),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: EripooButton(
            label: l10n.feesKeep,
            icon: Icons.check,
            variant: EripooButtonVariant.tertiary,
            onPressed: _keep,
          ),
        ),
      ],
    );
  }
}

/// The preparation as document parts (PDF and the file's chapter): what
/// the user collected, the documents ready or not, the estimate, and the
/// sources with their dates.
List<DocPart> preparationParts({
  required AppLocalizations l10n,
  required EripooFormatter formatter,
  required FormalizationContent content,
  required String Function(LocalizedText) text,
  required SectionSchema? schema,
  required Map<String, Object?> fields,
  required Preparation prep,
}) {
  FeeEstimate? estimate;
  final input = prep.feeInput;
  if (input != null && content.fees != null) {
    try {
      estimate = estimateCreationFees(content.fees!, input);
    } on InvalidFeeInput {
      estimate = null;
    }
  }
  return [
    DocPart(
      key: 'collected',
      title: l10n.prepCollected,
      items: [
        if (schema != null)
          for (final field in schema.fields)
            if ((fields[field.key]?.toString() ?? '').trim().isNotEmpty)
              DocLabeled(text(field.label), fields[field.key].toString()),
      ],
    ),
    DocPart(
      key: 'documents',
      title: l10n.formalizationChecklistTitle,
      items: [
        for (final item in content.checklist)
          DocBullet(
            prep.ready.contains(item.id)
                ? l10n.prepItemReady(text(item.text))
                : l10n.prepItemTodo(text(item.text)),
          ),
      ],
    ),
    DocPart(
      key: 'fees',
      title: l10n.feesTitle,
      items: [
        if (estimate != null) ...[
          for (final line in estimate.lines)
            DocLabeled(
              feeLineLabel(l10n, line.kind),
              formatter.money(line.amountMga),
            ),
          DocParagraph(l10n.feesTotal(formatter.money(estimate.totalMga))),
          DocParagraph(l10n.feesNote),
        ],
      ],
    ),
    DocPart(
      key: 'sources',
      title: l10n.formalizationSourcesTitle,
      items: [
        DocParagraph(
          l10n.formalizationNotice(
            formatter.date(
              content.sources
                  .map((s) => s.consulted)
                  .reduce((a, b) => a.isAfter(b) ? a : b),
            ),
          ),
        ),
        for (final s in content.sources)
          DocBullet('${s.publisher} — ${s.title} · ${s.url}'),
      ],
    ),
  ].where((p) => p.filled).toList();
}
