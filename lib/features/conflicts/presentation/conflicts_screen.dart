import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../quest/presentation/journey_providers.dart';
import '../application/conflict_service.dart';

final conflictServiceProvider = Provider<ConflictService>(
  (ref) => ConflictService(ref.watch(appDatabaseProvider)),
);

final _conflictTick = StreamProvider<int>((ref) {
  var tick = 0;
  return ref.watch(conflictServiceProvider).watchChanges().map((_) => ++tick);
});

/// Versions to decide, re-read when copies change.
final pendingConflictsProvider = FutureProvider<List<ConflictView>>((ref) {
  ref.watch(_conflictTick);
  return ref.watch(conflictServiceProvider).pending();
});

/// "Versions to check" (docs/OFFLINE_SYNC.md §6): the same element changed
/// on two phones; both versions were kept, the user chooses.
class ConflictsScreen extends ConsumerWidget {
  const ConflictsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pending = ref.watch(pendingConflictsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.conflictsTitle)),
      body: pending.when(
        loading: () => const EripooLoadingView(),
        error: (_, _) => const EripooErrorView(),
        data: (views) => ListView(
          padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
          children: [
            ReadableColumn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.conflictsExplain),
                  const SizedBox(height: EripooSpacing.lg),
                  if (views.isEmpty)
                    Text(
                      l10n.conflictsEmpty,
                      style: context.textStyles.titleMedium,
                    ),
                  for (final view in views) ...[
                    _ConflictCard(view),
                    const SizedBox(height: EripooSpacing.md),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConflictCard extends ConsumerWidget {
  const _ConflictCard(this.view);
  final ConflictView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final conflicts = ref.read(conflictServiceProvider);
    final empty = l10n.projectHistoryNoValue;
    return EripooCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.conflictEntity(view.entityType),
            style: context.textStyles.titleSmall,
          ),
          const SizedBox(height: EripooSpacing.sm),
          if (view.differences.isEmpty) Text(l10n.conflictNoDifference),
          for (final d in view.differences) ...[
            Text(l10n.conflictCurrent, style: context.textStyles.labelMedium),
            Text(d.current ?? empty),
            const SizedBox(height: EripooSpacing.xs),
            Text(
              l10n.conflictOther(
                context.formatter.dateShort(view.setAsideAt.toLocal()),
              ),
              style: context.textStyles.labelMedium,
            ),
            Text(d.other ?? empty),
            const Divider(),
          ],
          Wrap(
            spacing: EripooSpacing.sm,
            children: [
              EripooButton(
                label: l10n.conflictKeepCurrent,
                variant: EripooButtonVariant.tertiary,
                onPressed: () => conflicts.keepCurrent(view.id),
              ),
              if (view.differences.isNotEmpty)
                EripooButton(
                  label: l10n.conflictKeepOther,
                  variant: EripooButtonVariant.tertiary,
                  onPressed: () => conflicts.keepOther(view.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
