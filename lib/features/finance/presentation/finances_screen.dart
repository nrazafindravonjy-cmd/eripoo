import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../core/format/eripoo_formatter.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../hypotheses/presentation/research_forms.dart';
import '../../quest/presentation/journey_providers.dart';
import '../../trash/application/trash_service.dart';
import '../../trash/presentation/trash_screen.dart';
import '../application/finance_service.dart';
import '../domain/finance_math.dart';
import 'finance_providers.dart';

String financeKindTitle(AppLocalizations l10n, FinanceKind kind) =>
    l10n.financeKindTitle(kind.name);

String fundingSourceLabel(AppLocalizations l10n, FundingSource source) =>
    l10n.fundingSource(source.name);

/// Adds or edits an amount: the source first for money found, then the
/// label and the amount.
Future<void> editFinanceItem(
  BuildContext context,
  WidgetRef ref, {
  required String projectId,
  required FinanceKind kind,
  FinanceItem? current,
}) async {
  final l10n = AppLocalizations.of(context);
  FundingSource? source;
  if (kind == FinanceKind.funding) {
    source = await showChoiceSheet<FundingSource>(
      context,
      title: l10n.financeSourceQuestion,
      options: [
        for (final s in FundingSource.values) (s, fundingSourceLabel(l10n, s)),
      ],
    );
    if (source == null || !context.mounted) return;
  }
  final values = await showFieldsSheet(
    context,
    title: financeKindTitle(l10n, kind),
    note: l10n.financeKindHelp(kind.name),
    fields: [
      FieldSpec(
        'label',
        l10n.financeItemLabel,
        initial: current?.label,
        maxLength: FinanceItemRules.maxLabelLength,
      ),
      FieldSpec(
        'amount',
        l10n.financeItemAmount,
        initial: current?.amountMga.toString(),
        number: true,
      ),
    ],
  );
  if (values == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final service = ref.read(financeServiceProvider);
  final amount = parseAmount(values['amount']!);
  try {
    if (amount == null) throw const InvalidFinanceItem();
    if (current == null) {
      await service.add(
        projectId: projectId,
        kind: kind,
        label: values['label']!,
        amountMga: amount,
        source: source,
      );
    } else {
      await service.update(
        current.id,
        label: values['label']!,
        amountMga: amount,
        source: source,
      );
    }
  } on InvalidFinanceItem {
    messenger.showSnackBar(SnackBar(content: Text(l10n.financeItemInvalid)));
  }
}

/// Sets the price and the sales expected.
Future<void> editFinancePlan(
  BuildContext context,
  WidgetRef ref,
  String projectId,
  FinancePlan plan,
) async {
  final l10n = AppLocalizations.of(context);
  final values = await showFieldsSheet(
    context,
    title: l10n.financePlanTitle,
    fields: [
      FieldSpec(
        'price',
        l10n.financePriceLabel,
        initial: plan.priceMga?.toString(),
        optional: true,
        number: true,
      ),
      FieldSpec(
        'first',
        l10n.financeVolumeFirstLabel,
        initial: plan.volumeFirst?.toString(),
        optional: true,
        number: true,
      ),
      FieldSpec(
        'last',
        l10n.financeVolumeLastLabel,
        initial: plan.volumeLast?.toString(),
        optional: true,
        number: true,
      ),
    ],
  );
  if (values == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  int? read(String key) {
    final text = values[key]!;
    if (text.isEmpty) return null;
    return parseAmount(text) ?? (throw const InvalidFinanceItem());
  }

  try {
    await ref
        .read(financeServiceProvider)
        .savePlan(
          projectId,
          priceMga: read('price'),
          volumeFirst: read('first'),
          volumeLast: read('last'),
        );
  } on InvalidFinanceItem {
    messenger.showSnackBar(SnackBar(content: Text(l10n.financePlanInvalid)));
  }
}

/// The project's numbers (CLAUDE.md §17): costs, investment, money found,
/// price and sales, and what they mean, in plain words.
class FinancesScreen extends ConsumerWidget {
  const FinancesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final project = ref.watch(activeProjectProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.financeTitle)),
      body: project == null
          ? EripooMessageView(
              icon: Icons.work_outline,
              title: l10n.projectEmptyTitle,
              message: l10n.projectEmptyBody,
            )
          : ref
                .watch(financeSnapshotProvider(project.id))
                .when(
                  loading: () => const EripooLoadingView(),
                  error: (_, _) => const EripooErrorView(),
                  data: (s) => _FinanceBody(projectId: project.id, snapshot: s),
                ),
    );
  }
}

class _FinanceBody extends ConsumerWidget {
  const _FinanceBody({required this.projectId, required this.snapshot});

  final String projectId;
  final FinanceSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = snapshot;
    final f = context.formatter;
    final plan = s.plan;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
      children: [
        ReadableColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.financeIntro),
              for (final kind in FinanceKind.values) ...[
                const SizedBox(height: EripooSpacing.lg),
                _KindCard(projectId: projectId, kind: kind, snapshot: s),
              ],
              const SizedBox(height: EripooSpacing.lg),
              EripooCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.financePlanTitle,
                      style: context.textStyles.titleMedium,
                    ),
                    const SizedBox(height: EripooSpacing.xs),
                    if (plan.priceMga == null && !s.hasVolumes)
                      Text(l10n.financePlanEmpty),
                    if (plan.priceMga != null)
                      Text(l10n.financePlanPrice(f.money(plan.priceMga!))),
                    if (s.hasVolumes)
                      Text(
                        l10n.financePlanVolumes(
                          f.integer(plan.volumeFirst!),
                          f.integer(plan.volumeLast!),
                        ),
                      ),
                    EripooButton(
                      label: l10n.financePlanEdit,
                      icon: Icons.edit_outlined,
                      variant: EripooButtonVariant.tertiary,
                      onPressed: () =>
                          editFinancePlan(context, ref, projectId, plan),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: EripooSpacing.xl),
              Text(
                l10n.financeResultsTitle,
                style: context.textStyles.titleMedium,
              ),
              const SizedBox(height: EripooSpacing.sm),
              _Results(snapshot: s),
              const SizedBox(height: EripooSpacing.lg),
              EripooCard(
                onTap: () => context.go(AppRoutes.financing),
                child: Row(
                  children: [
                    const Icon(Icons.savings_outlined),
                    const SizedBox(width: EripooSpacing.md),
                    Expanded(child: Text(l10n.financeFindMoney)),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
              const SizedBox(height: EripooSpacing.lg),
              Text(
                l10n.financeNotPrediction,
                style: context.textStyles.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _KindCard extends ConsumerWidget {
  const _KindCard({
    required this.projectId,
    required this.kind,
    required this.snapshot,
  });

  final String projectId;
  final FinanceKind kind;
  final FinanceSnapshot snapshot;

  int get _total => switch (kind) {
    FinanceKind.variableCost => snapshot.unitCost,
    FinanceKind.fixedCost => snapshot.fixedMonthly,
    FinanceKind.investment => snapshot.investment,
    FinanceKind.funding => snapshot.funding,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final items = snapshot.ofKind(kind);
    return EripooCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            financeKindTitle(l10n, kind),
            style: context.textStyles.titleMedium,
          ),
          Text(
            l10n.financeKindHelp(kind.name),
            style: context.textStyles.bodySmall,
          ),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: EripooSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.label),
                        if (item.source != null)
                          Text(
                            fundingSourceLabel(l10n, item.source!),
                            style: context.textStyles.labelMedium,
                          ),
                      ],
                    ),
                  ),
                  Text(
                    context.formatter.money(item.amountMga),
                    style: context.textStyles.titleSmall,
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: l10n.competitorEdit,
                    onPressed: () => editFinanceItem(
                      context,
                      ref,
                      projectId: projectId,
                      kind: kind,
                      current: item,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: l10n.actionDelete,
                    onPressed: () => deleteWithUndo(
                      context,
                      ref,
                      TrashKind.financeItem,
                      item.id,
                    ),
                  ),
                ],
              ),
            ),
          if (items.isNotEmpty) ...[
            const Divider(),
            Text(
              l10n.financeTotal(context.formatter.money(_total)),
              style: context.textStyles.labelLarge,
            ),
          ],
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: EripooButton(
              label: l10n.financeAdd,
              icon: Icons.add,
              variant: EripooButtonVariant.tertiary,
              onPressed: () => editFinanceItem(
                context,
                ref,
                projectId: projectId,
                kind: kind,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the numbers mean, one sentence each; when an input is missing,
/// says which one instead of guessing.
class _Results extends StatelessWidget {
  const _Results({required this.snapshot});

  final FinanceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final f = context.formatter;
    final s = snapshot;
    final lines = <String>[];
    if (!s.hasUnitCost) lines.add(l10n.financeNeedUnitCost);
    final m = s.unitMargin;
    if (m == null) {
      lines.add(l10n.financeNeedPrice);
    } else {
      lines.add(
        m.isLoss
            ? l10n.financeMarginLoss(f.money(-m.unitMargin))
            : l10n.financeMarginResult(
                f.money(m.unitMargin),
                f.percentBp(m.marginBp ?? 0),
              ),
      );
      lines.add(breakEvenSentence(l10n, f, s.breakEvenPoint!));
    }
    final cash = s.cash;
    final gap = s.gap;
    if (cash == null || gap == null) {
      if (m != null) lines.add(l10n.financeNeedVolumes);
    } else {
      lines.add(l10n.financeCashNeed(f.money(gap.need)));
      lines.add(
        gap.covered
            ? l10n.financeCashCovered
            : l10n.financeCashMissing(f.money(gap.missing)),
      );
      final short = cash.firstShortMonth;
      if (short != null) lines.add(l10n.financeCashFirstShort(short));
      final recover = monthsToRecover(
        investment: s.investment,
        monthlyProfit: cash.months.last.net,
      );
      if (recover != null && s.investment > 0) {
        lines.add(l10n.financeRecover(recover));
      }
    }
    return EripooCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final line in lines) ...[
            Text(line),
            const SizedBox(height: EripooSpacing.sm),
          ],
          if (cash != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: EripooButton(
                label: l10n.financeCashOpen,
                icon: Icons.calendar_month_outlined,
                variant: EripooButtonVariant.tertiary,
                onPressed: () => context.go(AppRoutes.cashPlan),
              ),
            ),
        ],
      ),
    );
  }
}

/// The break-even point in one sentence.
String breakEvenSentence(
  AppLocalizations l10n,
  EripooFormatter f,
  BreakEven b,
) {
  if (!b.reachable) return l10n.financeBreakEvenImpossible;
  if (b.units == 0) return l10n.financeBreakEvenZero;
  if (b.beyondLimits) return l10n.financeBreakEvenTooHigh(f.integer(b.units!));
  return l10n.financeBreakEven(f.integer(b.units!), f.money(b.revenue!));
}
