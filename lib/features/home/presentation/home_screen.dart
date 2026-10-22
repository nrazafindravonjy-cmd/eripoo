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
import '../../usage/presentation/usage_opened_tracker.dart';
import 'erasure_notice.dart';

/// Home: the one recommended next action, and missions in progress.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final plan = ref.watch(journeyPlanProvider);
    final project = ref.watch(activeProjectProvider).value;
    final missions = ref.watch(missionsProvider).value ?? const [];
    final pack = ref.watch(contentPackProvider);
    return Scaffold(
      appBar: AppBar(title: Text(project?.title ?? l10n.navHome)),
      body: plan.when(
        loading: () => const EripooLoadingView(),
        error: (_, _) => const EripooErrorView(),
        data: (plan) {
          final next = plan.next;
          final open = missions.where((m) => m.status.isOpen).toList();
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
            children: [
              const ErasureNotice(),
              const NewDeviceNotice(),
              const BadgeCelebration(),
              const UsageOpenedTracker(),
              ReadableColumn(
                child: !plan.diagnosticDone
                    ? EripooCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.homeStartTitle,
                              style: context.textStyles.titleLarge,
                            ),
                            const SizedBox(height: EripooSpacing.sm),
                            Text(l10n.homeStartBody),
                            const SizedBox(height: EripooSpacing.lg),
                            EripooButton(
                              label: l10n.homeBegin,
                              expand: true,
                              onPressed: next == null
                                  ? null
                                  : () => context.push(
                                      AppRoutes.step(next.step.id),
                                    ),
                            ),
                          ],
                        ),
                      )
                    : next == null
                    ? EripooMessageView(
                        icon: Icons.emoji_events_outlined,
                        title: l10n.homeAllDoneTitle,
                        message: l10n.homeAllDoneBody,
                      )
                    : EripooCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.homeNextTitle,
                              style: context.textStyles.labelLarge,
                            ),
                            const SizedBox(height: EripooSpacing.sm),
                            Text(
                              contentText(
                                context,
                                pack.questOfStep(next.step.id)!.title,
                              ),
                              style: context.textStyles.bodyMedium,
                            ),
                            Text(
                              contentText(context, next.step.title),
                              style: context.textStyles.titleLarge,
                            ),
                            const SizedBox(height: EripooSpacing.lg),
                            EripooButton(
                              label: next.status == StepStatus.inProgress
                                  ? l10n.homeContinue
                                  : l10n.homeBegin,
                              expand: true,
                              onPressed: () =>
                                  context.push(AppRoutes.step(next.step.id)),
                            ),
                          ],
                        ),
                      ),
              ),
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
                          semanticLabel: contentText(context, template.title),
                          onTap: () =>
                              context.push(AppRoutes.mission(template.id)),
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
    );
  }
}
