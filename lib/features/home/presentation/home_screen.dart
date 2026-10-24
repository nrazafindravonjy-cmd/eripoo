import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../content/progress_state.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../badges/presentation/badges_screen.dart';
import '../../devices/presentation/new_device_notice.dart';
import '../../quest/presentation/content_widgets.dart';
import '../../quest/presentation/journey_providers.dart';
import '../../tips/presentation/feature_tip.dart';
import '../../usage/presentation/usage_opened_tracker.dart';
import 'erasure_notice.dart';
import 'home_dashboard.dart';

/// Home: a greeting, the one recommended next action (hero card), the
/// project's figures, the week's rhythm and missions in progress.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final plan = ref.watch(journeyPlanProvider);
    final project = ref.watch(activeProjectProvider).value;
    final missions = ref.watch(missionsProvider).value ?? const [];
    final pack = ref.watch(contentPackProvider);
    final dashboard = ref.watch(homeDashboardProvider).value;
    final now = DateTime.now();
    return Scaffold(
      body: Stack(
        children: [
          // A large, faint Eripoo mark half off screen: depth, not noise.
          const Positioned(
            top: -40,
            right: -90,
            child: Opacity(opacity: 0.05, child: EripooLogo(size: 280)),
          ),
          SafeArea(
            child: plan.when(
              loading: () => const EripooLoadingView(),
              error: (_, _) => const EripooErrorView(),
              data: (plan) {
                final next = plan.next;
                final open = missions.where((m) => m.status.isOpen).toList();
                final quest = next == null
                    ? null
                    : [?plan.diagnostic, ...plan.quests]
                          .where(
                            (q) =>
                                q.steps.any((s) => s.step.id == next.step.id),
                          )
                          .firstOrNull;
                return ListView(
                  padding: const EdgeInsets.symmetric(
                    vertical: EripooSpacing.xl,
                  ),
                  children: [
                    ReadableColumn(
                      child: HomeGreeting(
                        projectTitle: project?.title,
                        now: now,
                      ),
                    ),
                    const SizedBox(height: EripooSpacing.xl),
                    const ErasureNotice(),
                    const NewDeviceNotice(),
                    const BadgeCelebration(),
                    const UsageOpenedTracker(),
                    ReadableColumn(
                      child: !plan.diagnosticDone
                          ? FeatureTip(
                              id: 'home.hero',
                              message: l10n.tipHomeHero,
                              child: HomeHeroCard(
                                label: l10n.homeHeroLabel,
                                title: l10n.homeStartTitle,
                                subtitle: l10n.homeStartBody,
                                done: 0,
                                total: 0,
                                actionLabel: l10n.homeBegin,
                                onAction: next == null
                                    ? null
                                    : () => context.push(
                                        AppRoutes.step(next.step.id),
                                      ),
                              ),
                            )
                          : next == null
                          ? EripooMessageView(
                              icon: Icons.emoji_events_outlined,
                              title: l10n.homeAllDoneTitle,
                              message: l10n.homeAllDoneBody,
                            )
                          : HomeHeroCard(
                              label: l10n.homeHeroLabel,
                              title: contentText(
                                context,
                                pack.questOfStep(next.step.id)!.title,
                              ),
                              subtitle: contentText(context, next.step.title),
                              done: quest?.done ?? 0,
                              total: quest?.total ?? 0,
                              actionLabel: next.status == StepStatus.inProgress
                                  ? l10n.homeContinue
                                  : l10n.homeBegin,
                              onAction: () =>
                                  context.push(AppRoutes.step(next.step.id)),
                            ),
                    ),
                    if (plan.diagnosticDone && dashboard != null) ...[
                      const SizedBox(height: EripooSpacing.lg),
                      ReadableColumn(
                        child: FeatureTip(
                          id: 'home.stats',
                          message: l10n.tipHomeStats,
                          child: HomeStats(data: dashboard),
                        ),
                      ),
                      const SizedBox(height: EripooSpacing.md),
                      ReadableColumn(
                        child: FeatureTip(
                          id: 'home.week',
                          message: l10n.tipHomeWeek,
                          child: HomeWeek(days: dashboard.days, now: now),
                        ),
                      ),
                    ],
                    if (open.isNotEmpty) ...[
                      const SizedBox(height: EripooSpacing.xl),
                      ReadableColumn(
                        child: Text(
                          l10n.homeMissionsTitle,
                          style: context.textStyles.titleMedium,
                        ),
                      ),
                      const SizedBox(height: EripooSpacing.sm),
                      for (final m in open)
                        if (pack.mission(m.templateId) case final template?)
                          ReadableColumn(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                bottom: EripooSpacing.sm,
                              ),
                              child: EripooCard(
                                semanticLabel: contentText(
                                  context,
                                  template.title,
                                ),
                                onTap: () => context.push(
                                  AppRoutes.mission(template.id),
                                ),
                                child: Text(
                                  contentText(context, template.title),
                                  style: context.textStyles.titleSmall,
                                ),
                              ),
                            ),
                          ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
