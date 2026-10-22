import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../quest/presentation/journey_providers.dart';
import '../../tools/presentation/guide_view.dart';
import 'finance_providers.dart';

/// The first twelve months, one line each: sales, costs, what is left.
class CashPlanScreen extends ConsumerWidget {
  const CashPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final f = context.formatter;
    final project = ref.watch(activeProjectProvider).value;
    final cash = project == null
        ? null
        : ref.watch(financeSnapshotProvider(project.id)).value?.cash;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.financeCashTitle)),
      body: cash == null
          ? EripooMessageView(
              icon: Icons.calendar_month_outlined,
              title: l10n.financeCashTitle,
              message: l10n.financeNeedVolumes,
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
              children: [
                ReadableColumn(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(l10n.financeCashIntro),
                      const SizedBox(height: EripooSpacing.md),
                      Text(
                        l10n.financeCashStart(
                          f.money(cash.startingCash - cash.investment),
                        ),
                        style: context.textStyles.labelLarge,
                      ),
                      for (final m in cash.months) ...[
                        const SizedBox(height: EripooSpacing.sm),
                        EripooCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.financeCashMonth(m.month),
                                style: context.textStyles.titleSmall,
                              ),
                              Text(l10n.financeCashUnits(f.integer(m.volume))),
                              Text(
                                l10n.financeCashRow(
                                  f.money(m.revenue),
                                  f.money(m.costs),
                                ),
                              ),
                              Text(
                                l10n.financeCashEnd(f.money(m.closing)),
                                style: context.textStyles.labelLarge?.copyWith(
                                  color: m.closing < 0
                                      ? context.colors.danger.base
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// How to find money (CLAUDE.md §49), from content.
class FinancingGuideScreen extends ConsumerWidget {
  const FinancingGuideScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final guide = ref.watch(contentPackProvider).financingGuide;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.financingGuideTitle)),
      body: ListView(
        padding: const EdgeInsets.all(EripooSpacing.lg),
        children: [ReadableColumn(child: GuideSectionsView(sections: guide))],
      ),
    );
  }
}
