import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../quest/presentation/journey_providers.dart';
import '../domain/research.dart';
import 'research_forms.dart';
import 'research_providers.dart';

/// The project's hypotheses: what the user believes and has not checked.
class HypothesesScreen extends ConsumerWidget {
  const HypothesesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final project = ref.watch(activeProjectProvider).value;
    final list = project == null
        ? null
        : ref.watch(hypothesesProvider(project.id));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.hypothesesTitle)),
      floatingActionButton: project == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showHypothesisForm(context, ref, project.id),
              icon: const Icon(Icons.add),
              label: Text(l10n.hypothesisNew),
            ),
      body: list == null
          ? EripooMessageView(
              icon: Icons.work_outline,
              title: l10n.projectEmptyTitle,
              message: l10n.projectEmptyBody,
            )
          : list.when(
              loading: () => const EripooLoadingView(),
              error: (_, _) => const EripooErrorView(),
              data: (hypotheses) => hypotheses.isEmpty
                  ? EripooMessageView(
                      icon: Icons.science_outlined,
                      title: l10n.hypothesesTitle,
                      message: l10n.hypothesesEmpty,
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        0,
                        EripooSpacing.lg,
                        0,
                        96,
                      ),
                      children: [
                        ReadableColumn(
                          child: _StatusFilters(hypotheses: hypotheses),
                        ),
                        for (final h in hypotheses.reversed.where(
                          (h) =>
                              ref.watch(hypothesisFilterProvider).isEmpty ||
                              ref
                                  .watch(hypothesisFilterProvider)
                                  .contains(h.status),
                        ))
                          ReadableColumn(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                bottom: EripooSpacing.md,
                              ),
                              child: _HypothesisCard(h),
                            ),
                          ),
                      ],
                    ),
            ),
    );
  }
}

/// Statuses shown in the list; empty means all. Kept while the user goes
/// back and forth (rule 11).
class HypothesisFilter extends Notifier<Set<HypothesisStatus>> {
  @override
  Set<HypothesisStatus> build() => const {};

  void toggle(HypothesisStatus status) => state = state.contains(status)
      ? ({...state}..remove(status))
      : {...state, status};

  void clear() => state = const {};
}

final hypothesisFilterProvider =
    NotifierProvider<HypothesisFilter, Set<HypothesisStatus>>(
      HypothesisFilter.new,
    );

/// Pastilles of the statuses present; an active one shows a cross to
/// remove it in one gesture.
class _StatusFilters extends ConsumerWidget {
  const _StatusFilters({required this.hypotheses});

  final List<Hypothesis> hypotheses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final active = ref.watch(hypothesisFilterProvider);
    final filter = ref.read(hypothesisFilterProvider.notifier);
    final present = [
      for (final s in HypothesisStatus.values)
        if (hypotheses.any((h) => h.status == s)) s,
    ];
    if (present.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: EripooSpacing.md),
      child: Wrap(
        spacing: EripooSpacing.sm,
        runSpacing: EripooSpacing.xs,
        children: [
          for (final s in present)
            FilterChip(
              label: Text(statusLabel(l10n, s)),
              selected: active.contains(s),
              onSelected: (_) => filter.toggle(s),
              onDeleted: active.contains(s) ? () => filter.toggle(s) : null,
              deleteButtonTooltipMessage: l10n.filterRemove(
                statusLabel(l10n, s),
              ),
            ),
          if (active.isNotEmpty)
            ActionChip(label: Text(l10n.filterAll), onPressed: filter.clear),
        ],
      ),
    );
  }
}

class _HypothesisCard extends StatelessWidget {
  const _HypothesisCard(this.h);
  final Hypothesis h;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EripooCard(
      onTap: () => context.go(AppRoutes.hypothesis(h.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(h.statement, style: context.textStyles.bodyLarge),
          const SizedBox(height: EripooSpacing.sm),
          Wrap(
            spacing: EripooSpacing.sm,
            runSpacing: EripooSpacing.xs,
            children: [
              Chip(label: Text(statusLabel(l10n, h.status))),
              Chip(label: Text(categoryLabel(l10n, h.category))),
            ],
          ),
        ],
      ),
    );
  }
}

/// Creates a hypothesis, or edits [existing] (draft or to test only).
Future<void> showHypothesisForm(
  BuildContext context,
  WidgetRef ref,
  String projectId, {
  Hypothesis? existing,
}) => showFormSheet<void>(
  context,
  builder: (_) => _HypothesisForm(projectId: projectId, existing: existing),
);

class _HypothesisForm extends ConsumerStatefulWidget {
  const _HypothesisForm({required this.projectId, this.existing});
  final String projectId;
  final Hypothesis? existing;

  @override
  ConsumerState<_HypothesisForm> createState() => _HypothesisFormState();
}

class _HypothesisFormState extends ConsumerState<_HypothesisForm> {
  late final _statement = TextEditingController(
    text: widget.existing?.statement,
  );
  late var _category = widget.existing?.category ?? HypothesisCategory.problem;
  late var _importance = widget.existing?.importance ?? 2;
  late var _confidence = widget.existing?.confidenceBefore ?? 3;
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
    final research = ref.read(researchServiceProvider);
    final navigator = Navigator.of(context);
    final existing = widget.existing;
    final ok = await runGuarded(
      context,
      () => existing == null
          ? research.createHypothesis(
              projectId: widget.projectId,
              statement: _statement.text,
              category: _category,
              importance: _importance,
              confidenceBefore: _confidence,
            )
          : research.editHypothesis(
              existing.id,
              statement: _statement.text,
              category: _category,
              importance: _importance,
              confidenceBefore: _confidence,
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
        Text(
          widget.existing == null ? l10n.hypothesisNew : l10n.hypothesisEdit,
          style: context.textStyles.titleLarge,
        ),
        const SizedBox(height: EripooSpacing.md),
        EripooTextField(
          label: l10n.hypothesisStatementLabel,
          helper: l10n.hypothesisTemplate,
          controller: _statement,
          minLines: 2,
          maxLines: 5,
          maxLength: HypothesisRules.maxStatementLength,
          errorText: _empty ? l10n.guardInvalidText : null,
        ),
        const SizedBox(height: EripooSpacing.md),
        Text(
          l10n.hypothesisCategoryLabel,
          style: context.textStyles.labelLarge,
        ),
        Wrap(
          spacing: EripooSpacing.sm,
          children: [
            for (final c in HypothesisCategory.values)
              ChoiceChip(
                label: Text(categoryLabel(l10n, c)),
                selected: c == _category,
                onSelected: (_) => setState(() => _category = c),
              ),
          ],
        ),
        const SizedBox(height: EripooSpacing.md),
        Text(
          l10n.hypothesisImportanceLabel,
          style: context.textStyles.labelLarge,
        ),
        Wrap(
          spacing: EripooSpacing.sm,
          children: [
            for (final (v, label) in [
              (1, l10n.importance1),
              (2, l10n.importance2),
              (3, l10n.importance3),
            ])
              ChoiceChip(
                label: Text(label),
                selected: v == _importance,
                onSelected: (_) => setState(() => _importance = v),
              ),
          ],
        ),
        const SizedBox(height: EripooSpacing.md),
        ConfidencePicker(
          label: l10n.hypothesisConfidenceLabel(_confidence),
          value: _confidence,
          onChanged: (v) => setState(() => _confidence = v),
        ),
        const SizedBox(height: EripooSpacing.lg),
        EripooButton(label: l10n.actionSave, expand: true, onPressed: _save),
      ],
    );
  }
}
