import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/research.dart';
import 'hypotheses_screen.dart';
import 'research_forms.dart';
import 'research_providers.dart';

/// One hypothesis and its tests: experiments, results, evidence,
/// conclusions and the decision journal. Every action shown is one the
/// state machine allows; the service still checks every rule.
class HypothesisScreen extends ConsumerWidget {
  const HypothesisScreen({super.key, required this.hypothesisId});
  final String hypothesisId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(hypothesisDetailProvider(hypothesisId));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.hypothesesTitle)),
      body: detail.when(
        loading: () => const EripooLoadingView(),
        error: (_, _) => const EripooErrorView(),
        data: (d) => d == null
            ? const EripooErrorView()
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
                children: [ReadableColumn(child: _Detail(d))],
              ),
      ),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail(this.d);
  final HypothesisDetail d;

  Hypothesis get h => d.hypothesis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final research = ref.read(researchServiceProvider);
    final status = h.status;
    final canTest =
        status == HypothesisStatus.draft ||
        status == HypothesisStatus.toTest ||
        status == HypothesisStatus.testing ||
        status == HypothesisStatus.inconclusive;
    final canAbandon = HypothesisMachine.canMove(
      status,
      HypothesisStatus.abandoned,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(h.statement, style: context.textStyles.titleLarge),
        const SizedBox(height: EripooSpacing.sm),
        Wrap(
          spacing: EripooSpacing.sm,
          runSpacing: EripooSpacing.xs,
          children: [
            Chip(label: Text(statusLabel(l10n, status))),
            Chip(label: Text(categoryLabel(l10n, h.category))),
          ],
        ),
        if (h.parentHypothesisId != null)
          _VersionLink(
            label: l10n.hypothesisPreviousVersion,
            id: h.parentHypothesisId!,
          ),
        if (d.child != null)
          _VersionLink(label: l10n.hypothesisNextVersion, id: d.child!.id),
        if (!status.isEditable && status != HypothesisStatus.abandoned) ...[
          const SizedBox(height: EripooSpacing.sm),
          Text(l10n.hypothesisLockedNote, style: context.textStyles.bodySmall),
        ],
        if (status == HypothesisStatus.invalidated) ...[
          const SizedBox(height: EripooSpacing.md),
          EripooCard(child: Text(l10n.invalidatedEncouragement)),
        ],
        const SizedBox(height: EripooSpacing.md),
        Wrap(
          spacing: EripooSpacing.sm,
          runSpacing: EripooSpacing.sm,
          children: [
            if (status.isEditable)
              EripooButton(
                label: l10n.hypothesisEdit,
                icon: Icons.edit_outlined,
                variant: EripooButtonVariant.secondary,
                onPressed: () =>
                    showHypothesisForm(context, ref, h.projectId, existing: h),
              ),
            if (status == HypothesisStatus.draft)
              EripooButton(
                label: l10n.hypothesisMarkToTest,
                variant: EripooButtonVariant.secondary,
                onPressed: () =>
                    runGuarded(context, () => research.markToTest(h.id)),
              ),
            if (canTest)
              EripooButton(
                label: l10n.experimentPlan,
                icon: Icons.science_outlined,
                onPressed: () => _planExperiment(context, ref),
              ),
            if (status == HypothesisStatus.testing)
              EripooButton(
                label: l10n.conclude,
                icon: Icons.flag_outlined,
                onPressed: () => showFormSheet<void>(
                  context,
                  builder: (_) => _ConclusionForm(d),
                ),
              ),
            if (HypothesisRules.decisionsFor(status).isNotEmpty)
              EripooButton(
                label: l10n.decisionTake,
                icon: Icons.alt_route,
                onPressed: () => _decide(context, ref),
              ),
            if (canAbandon)
              EripooButton(
                label: l10n.hypothesisAbandon,
                variant: EripooButtonVariant.tertiary,
                onPressed: () => _abandon(context, ref),
              ),
          ],
        ),
        if (d.experiments.isNotEmpty) ...[
          const SizedBox(height: EripooSpacing.xl),
          Text(l10n.experimentsTitle, style: context.textStyles.titleMedium),
          for (final e in d.experiments) ...[
            const SizedBox(height: EripooSpacing.sm),
            _ExperimentCard(experiment: e, detail: d),
          ],
        ],
        if (d.conclusions.isNotEmpty) ...[
          const SizedBox(height: EripooSpacing.xl),
          Text(l10n.conclusionsTitle, style: context.textStyles.titleMedium),
          for (final c in d.conclusions)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(c.statement),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(statusLabel(l10n, c.outcome)),
                  Text(
                    l10n.conclusionConfidenceChange(
                      h.confidenceBefore == null
                          ? '–'
                          : context.formatter.integer(h.confidenceBefore!),
                      c.confidenceAfter,
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (d.decisions.isNotEmpty) ...[
          const SizedBox(height: EripooSpacing.xl),
          Text(l10n.decisionsTitle, style: context.textStyles.titleMedium),
          for (final decision in d.decisions)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bookmark_border),
              title: Text(decisionLabel(l10n, decision.kind)),
              subtitle: Text(decision.rationale),
            ),
        ],
      ],
    );
  }

  Future<void> _planExperiment(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final method = await showChoiceSheet<ExperimentMethod>(
      context,
      title: l10n.experimentMethodLabel,
      options: [
        for (final m in ExperimentMethod.values) (m, methodLabel(l10n, m)),
      ],
    );
    if (method == null || !context.mounted) return;
    final values = await showFieldsSheet(
      context,
      title: l10n.experimentPlan,
      fields: [
        FieldSpec(
          'plan',
          l10n.experimentPlanLabel,
          maxLines: 4,
          maxLength: ExperimentRules.maxPlanLength,
        ),
        FieldSpec(
          'criterion',
          l10n.experimentCriterionLabel,
          helper: l10n.experimentCriterionHelp,
          maxLines: 3,
          maxLength: ExperimentRules.maxCriterionLength,
          optional: true,
        ),
        FieldSpec(
          'sample',
          l10n.experimentSampleLabel,
          optional: true,
          number: true,
        ),
      ],
    );
    if (values == null || !context.mounted) return;
    await runGuarded(
      context,
      () => ref
          .read(researchServiceProvider)
          .planExperiment(
            projectId: h.projectId,
            method: method,
            plan: values['plan']!,
            hypothesisIds: [h.id],
            successCriterion: values['criterion'],
            sampleTarget: int.tryParse(values['sample'] ?? ''),
          ),
    );
  }

  Future<void> _decide(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final kind = await showChoiceSheet<DecisionKind>(
      context,
      title: l10n.decisionTake,
      options: [
        for (final k in DecisionKind.values)
          if (HypothesisRules.decisionsFor(h.status).contains(k))
            (k, decisionLabel(l10n, k)),
      ],
    );
    if (kind == null || !context.mounted) return;
    final values = await showFieldsSheet(
      context,
      title: decisionLabel(l10n, kind),
      fields: [
        if (kind == DecisionKind.modify)
          FieldSpec(
            'statement',
            l10n.decisionNewStatementLabel,
            helper: l10n.hypothesisTemplate,
            initial: h.statement,
            maxLines: 4,
            maxLength: HypothesisRules.maxStatementLength,
          ),
        FieldSpec(
          'why',
          l10n.decisionRationaleLabel,
          maxLines: 4,
          maxLength: HypothesisRules.maxRationaleLength,
        ),
      ],
    );
    if (values == null || !context.mounted) return;
    await runGuarded(
      context,
      () => ref
          .read(researchServiceProvider)
          .decide(
            h.id,
            kind: kind,
            rationale: values['why']!,
            newStatement: values['statement'],
          ),
    );
  }

  Future<void> _abandon(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showEripooConfirmDialog(
      context,
      title: l10n.hypothesisAbandonConfirmTitle,
      message: l10n.hypothesisAbandonConfirmBody,
      confirmLabel: l10n.hypothesisAbandon,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await runGuarded(
      context,
      () => ref.read(researchServiceProvider).abandon(h.id),
    );
  }
}

class _VersionLink extends StatelessWidget {
  const _VersionLink({required this.label, required this.id});
  final String label;
  final String id;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: EripooButton(
      label: label,
      icon: Icons.call_split,
      variant: EripooButtonVariant.tertiary,
      onPressed: () => context.go(AppRoutes.hypothesis(id)),
    ),
  );
}

class _ExperimentCard extends ConsumerWidget {
  const _ExperimentCard({required this.experiment, required this.detail});
  final Experiment experiment;
  final HypothesisDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final e = experiment;
    final research = ref.read(researchServiceProvider);
    final results = detail.results[e.id] ?? const <ExperimentResult>[];
    final projectId = detail.hypothesis.projectId;
    return EripooCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  methodLabel(l10n, e.method),
                  style: context.textStyles.titleMedium,
                ),
              ),
              Chip(label: Text(experimentStatusLabel(l10n, e.status))),
            ],
          ),
          Text(e.plan),
          const SizedBox(height: EripooSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                e.criterionLockedAt != null ? Icons.lock_outline : Icons.flag,
                size: 18,
              ),
              const SizedBox(width: EripooSpacing.xs),
              Expanded(
                child: Text(
                  e.successCriterion == null
                      ? l10n.experimentNoCriterion
                      : e.criterionLockedAt != null
                      ? l10n.experimentCriterionLocked(e.successCriterion!)
                      : e.successCriterion!,
                  style: context.textStyles.bodySmall,
                ),
              ),
            ],
          ),
          for (final r in results) ...[
            const Divider(),
            Text(r.summary),
            if (r.yes != null && r.total != null)
              Text(
                l10n.resultMetric(r.yes!, r.total!),
                style: context.textStyles.labelLarge,
              ),
            EvidenceList(
              evidences: detail.evidences[r.id] ?? const [],
              projectId: projectId,
              subject: EvidenceSubject.result,
              subjectId: r.id,
            ),
          ],
          if (e.status != ExperimentStatus.planned) ...[
            const Divider(),
            EvidenceList(
              evidences: detail.evidences[e.id] ?? const [],
              projectId: projectId,
              subject: EvidenceSubject.experiment,
              subjectId: e.id,
            ),
          ],
          Wrap(
            spacing: EripooSpacing.sm,
            runSpacing: EripooSpacing.xs,
            children: [
              if (e.status == ExperimentStatus.planned) ...[
                EripooButton(
                  label: l10n.projectEditSection,
                  variant: EripooButtonVariant.tertiary,
                  onPressed: () => _edit(context, ref),
                ),
                EripooButton(
                  label: l10n.experimentStart,
                  icon: Icons.play_arrow,
                  onPressed: () =>
                      runGuarded(context, () => research.startExperiment(e.id)),
                ),
              ],
              if (e.status == ExperimentStatus.running ||
                  e.status == ExperimentStatus.done)
                EripooButton(
                  label: l10n.experimentAddResult,
                  icon: Icons.add,
                  variant: EripooButtonVariant.secondary,
                  onPressed: () => _addResult(context, ref),
                ),
              if (e.status == ExperimentStatus.running)
                EripooButton(
                  label: l10n.experimentFinish,
                  variant: EripooButtonVariant.secondary,
                  onPressed: () => runGuarded(
                    context,
                    () => research.finishExperiment(e.id),
                  ),
                ),
              if (!e.status.isFinished)
                EripooButton(
                  label: l10n.experimentCancel,
                  variant: EripooButtonVariant.tertiary,
                  onPressed: () => _cancel(context, ref),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final e = experiment;
    final values = await showFieldsSheet(
      context,
      title: l10n.experimentPlan,
      fields: [
        FieldSpec(
          'plan',
          l10n.experimentPlanLabel,
          initial: e.plan,
          maxLines: 4,
          maxLength: ExperimentRules.maxPlanLength,
        ),
        FieldSpec(
          'criterion',
          l10n.experimentCriterionLabel,
          helper: l10n.experimentCriterionHelp,
          initial: e.successCriterion,
          maxLines: 3,
          maxLength: ExperimentRules.maxCriterionLength,
        ),
        FieldSpec(
          'sample',
          l10n.experimentSampleLabel,
          initial: e.sampleTarget?.toString(),
          optional: true,
          number: true,
        ),
      ],
    );
    if (values == null || !context.mounted) return;
    await runGuarded(
      context,
      () => ref
          .read(researchServiceProvider)
          .editExperiment(
            e.id,
            plan: values['plan'],
            successCriterion: values['criterion'],
            sampleTarget: int.tryParse(values['sample'] ?? ''),
          ),
    );
  }

  Future<void> _addResult(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final values = await showFieldsSheet(
      context,
      title: l10n.experimentAddResult,
      fields: [
        FieldSpec(
          'summary',
          l10n.resultSummaryLabel,
          maxLines: 4,
          maxLength: FieldNoteRules.maxShortLength,
        ),
        FieldSpec('yes', l10n.resultYesLabel, optional: true, number: true),
        FieldSpec('total', l10n.resultTotalLabel, optional: true, number: true),
      ],
    );
    if (values == null || !context.mounted) return;
    await runGuarded(
      context,
      () => ref
          .read(researchServiceProvider)
          .recordResult(
            experiment.id,
            summary: values['summary']!,
            yes: int.tryParse(values['yes'] ?? ''),
            total: int.tryParse(values['total'] ?? ''),
          ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showEripooConfirmDialog(
      context,
      title: l10n.experimentCancelConfirmTitle,
      message: l10n.experimentCancelConfirmBody,
      confirmLabel: l10n.experimentCancel,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await runGuarded(
      context,
      () => ref.read(researchServiceProvider).cancelExperiment(experiment.id),
    );
  }
}

class _ConclusionForm extends ConsumerStatefulWidget {
  const _ConclusionForm(this.detail);
  final HypothesisDetail detail;

  @override
  ConsumerState<_ConclusionForm> createState() => _ConclusionFormState();
}

class _ConclusionFormState extends ConsumerState<_ConclusionForm> {
  final _statement = TextEditingController();
  var _outcome = HypothesisStatus.validated;
  var _confidence = 3;
  bool _empty = false;

  @override
  void dispose() {
    _statement.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_statement.text.trim().isEmpty) {
      setState(() => _empty = true);
      return;
    }
    final navigator = Navigator.of(context);
    final experiments = widget.detail.experiments;
    final ok = await runGuarded(
      context,
      () => ref
          .read(researchServiceProvider)
          .conclude(
            widget.detail.hypothesis.id,
            outcome: _outcome,
            statement: _statement.text,
            confidenceAfter: _confidence,
            experimentId: experiments.isEmpty ? null : experiments.last.id,
          ),
    );
    if (ok) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.conclude, style: context.textStyles.titleLarge),
        const SizedBox(height: EripooSpacing.md),
        Text(l10n.conclusionOutcomeLabel, style: context.textStyles.labelLarge),
        Wrap(
          spacing: EripooSpacing.sm,
          children: [
            for (final o in [
              HypothesisStatus.validated,
              HypothesisStatus.invalidated,
              HypothesisStatus.inconclusive,
            ])
              ChoiceChip(
                label: Text(statusLabel(l10n, o)),
                selected: o == _outcome,
                onSelected: (_) => setState(() => _outcome = o),
              ),
          ],
        ),
        const SizedBox(height: EripooSpacing.md),
        EripooTextField(
          label: l10n.conclusionStatementLabel,
          controller: _statement,
          minLines: 2,
          maxLines: 5,
          maxLength: HypothesisRules.maxConclusionLength,
          errorText: _empty ? l10n.guardInvalidText : null,
        ),
        const SizedBox(height: EripooSpacing.md),
        ConfidencePicker(
          label: l10n.conclusionConfidenceLabel(_confidence),
          value: _confidence,
          onChanged: (v) => setState(() => _confidence = v),
        ),
        const SizedBox(height: EripooSpacing.lg),
        EripooButton(label: l10n.conclude, expand: true, onPressed: _save),
      ],
    );
  }
}
