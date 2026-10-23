import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../finance/presentation/finance_providers.dart';
import '../../hypotheses/domain/research.dart';
import '../../hypotheses/presentation/research_providers.dart';
import '../../quest/presentation/journey_providers.dart';

/// Figures of the project shown on Home: all already recorded on the
/// phone, nothing asked again.
class HomeDashboard {
  const HomeDashboard({
    required this.stepsDone,
    required this.stepsTotal,
    required this.stepsThisWeek,
    required this.activeDays,
    required this.hypothesesValidated,
    required this.hypothesesTotal,
    required this.notes,
    required this.priceMga,
  });

  final int stepsDone;
  final int stepsTotal;
  final int stepsThisWeek;

  /// Days (local midnight) on which a step or a mission was completed.
  final Set<DateTime> activeDays;
  final int hypothesesValidated;
  final int hypothesesTotal;
  final int notes;
  final int? priceMga;
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

final homeDashboardProvider = FutureProvider<HomeDashboard?>((ref) async {
  final plan = await ref.watch(journeyPlanProvider.future);
  final project = await ref.watch(activeProjectProvider.future);
  final input = await ref.watch(journeyServiceProvider).input();
  final completions = [
    for (final s in input.steps.values) ?s.completedAt,
    for (final m in input.missions.values) ?m.completedAt,
  ];
  final weekAgo = input.now.subtract(const Duration(days: 7));
  final quests = [?plan.diagnostic, ...plan.quests];
  final hypotheses = project == null
      ? const <Hypothesis>[]
      : await ref.watch(hypothesesProvider(project.id).future);
  final notes = project == null
      ? null
      : await ref.watch(fieldNotesProvider(project.id).future);
  final finance = project == null
      ? null
      : await ref.watch(financeSnapshotProvider(project.id).future);
  return HomeDashboard(
    stepsDone: quests.fold(0, (s, q) => s + q.done),
    stepsTotal: quests.fold(0, (s, q) => s + q.total),
    stepsThisWeek: [for (final s in input.steps.values) ?s.completedAt]
        .where((t) => t.isAfter(weekAgo))
        .length,
    activeDays: {for (final t in completions) _day(t)},
    hypothesesValidated: hypotheses
        .where((h) => h.status == HypothesisStatus.validated)
        .length,
    hypothesesTotal: hypotheses.length,
    notes: notes?.count ?? 0,
    priceMga: finance?.plan.priceMga,
  );
});

/// "Bonsoir" and the project's name, instead of a bare "Home" title. No
/// first name is asked for (rule 43).
class HomeGreeting extends StatelessWidget {
  const HomeGreeting({super.key, this.projectTitle, required this.now});

  final String? projectTitle;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final greeting = now.hour < 12
        ? l10n.greetingMorning
        : now.hour < 18
        ? l10n.greetingAfternoon
        : l10n.greetingEvening;
    final title = projectTitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EripooHeadline('*$greeting*', style: context.textStyles.displaySmall),
        if (title != null)
          Text(
            title,
            style: context.textStyles.titleMedium?.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
      ],
    );
  }
}

/// The yellow hero card: the quest in progress, its progress drawn as the
/// Eripoo mark, and the one action of the screen.
class HomeHeroCard extends StatelessWidget {
  const HomeHeroCard({
    super.key,
    required this.label,
    required this.title,
    required this.subtitle,
    required this.done,
    required this.total,
    required this.actionLabel,
    required this.onAction,
  });

  final String label;
  final String title;
  final String subtitle;
  final int done;
  final int total;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.textStyles;
    final ink = c.brand.onBase;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: c.brand.base,
        shape: const EripooCutBorder(radius: EripooRadii.xl, cut: 28),
      ),
      child: Padding(
        padding: const EdgeInsets.all(EripooSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: t.labelMedium?.copyWith(color: ink)),
                      const SizedBox(height: EripooSpacing.xs),
                      Text(title, style: t.headlineSmall?.copyWith(color: ink)),
                      const SizedBox(height: EripooSpacing.xs),
                      Text(subtitle, style: t.bodyMedium?.copyWith(color: ink)),
                    ],
                  ),
                ),
                if (total > 0) ...[
                  const SizedBox(width: EripooSpacing.md),
                  EripooProgressMark(
                    value: done / total,
                    center: '$done',
                    size: 64,
                    color: ink,
                    trackColor: c.brand.onBase.withValues(alpha: 0.2),
                  ),
                ],
              ],
            ),
            const SizedBox(height: EripooSpacing.xl),
            _DarkAction(label: actionLabel, onPressed: onAction),
          ],
        ),
      ),
    );
  }
}

/// The hero card's action: dark on yellow, with a yellow arrow pastille
/// (the inverse of the primary button, same gesture).
class _DarkAction extends StatelessWidget {
  const _DarkAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: c.brand.onBase,
            foregroundColor: c.textPrimary,
            padding: const EdgeInsets.only(
              left: EripooSpacing.sm,
              right: EripooSpacing.xl,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.brand.base,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_forward,
                  size: 20,
                  color: c.brand.onBase,
                ),
              ),
              const SizedBox(width: EripooSpacing.md),
              Expanded(child: Center(child: Text(label))),
              const SizedBox(width: 40),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two-by-two figures of the project, each opening its tool.
class HomeStats extends StatelessWidget {
  const HomeStats({super.key, required this.data});

  final HomeDashboard data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final f = context.formatter;
    final price = data.priceMga;
    final cards = [
      EripooStatCard(
        icon: Icons.flag_outlined,
        label: l10n.statSteps,
        value: l10n.statFraction(data.stepsDone, data.stepsTotal),
        badge: data.stepsThisWeek > 0
            ? l10n.deltaThisWeek(data.stepsThisWeek)
            : null,
        onTap: () => context.go(AppRoutes.quest),
      ),
      EripooStatCard(
        icon: Icons.science_outlined,
        label: l10n.statHypotheses,
        value: l10n.statFraction(
          data.hypothesesValidated,
          data.hypothesesTotal,
        ),
        onTap: () => context.push(AppRoutes.hypotheses),
      ),
      EripooStatCard(
        icon: Icons.edit_note,
        label: l10n.statNotes,
        value: f.integer(data.notes),
        onTap: () => context.push(AppRoutes.fieldNotes),
      ),
      EripooStatCard(
        icon: Icons.sell_outlined,
        label: l10n.statPrice,
        value: price == null ? l10n.statPriceNone : f.money(price),
        onTap: () => context.push(AppRoutes.priceCalculator),
      ),
    ];
    return Column(
      children: [
        for (var i = 0; i < cards.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: EripooSpacing.md),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[i]),
                  const SizedBox(width: EripooSpacing.md),
                  Expanded(child: cards[i + 1]),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The last seven days, ending today.
class HomeWeek extends StatelessWidget {
  const HomeWeek({super.key, required this.activeDays, required this.now});

  final Set<DateTime> activeDays;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final f = context.formatter;
    final today = _day(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.activityTitle, style: context.textStyles.titleMedium),
        const SizedBox(height: EripooSpacing.sm),
        EripooWeekStrip(
          days: [
            for (var i = 6; i >= 0; i--)
              () {
                final d = today.subtract(Duration(days: i));
                final name = f.weekday(d);
                final active = activeDays.contains(d);
                return EripooDay(
                  letter: name.substring(0, 1).toUpperCase(),
                  number: '${d.day}',
                  active: active,
                  today: i == 0,
                  semanticLabel: active
                      ? l10n.activityDayDone('$name ${d.day}')
                      : l10n.activityDayNone('$name ${d.day}'),
                );
              }(),
          ],
        ),
      ],
    );
  }
}
