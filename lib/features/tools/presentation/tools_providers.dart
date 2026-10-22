import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../quest/presentation/journey_providers.dart';
import '../application/competitor_service.dart';
import '../application/tool_service.dart';

final toolServiceProvider = Provider<ToolService>((ref) {
  final journey = ref.watch(journeyServiceProvider);
  return ToolService(
    ref.watch(appDatabaseProvider),
    ref.watch(contentPackProvider),
    input: journey.input,
  );
});

final _toolTick = StreamProvider<int>((ref) {
  var tick = 0;
  return ref.watch(toolServiceProvider).watchChanges().map((_) => ++tick);
});

/// Every tool and its state; unlocks are evaluated each time what the
/// rules read changes (so a tool unlocks wherever the user is).
final toolsProvider = FutureProvider<List<ToolState>>((ref) async {
  ref.watch(_toolTick);
  final service = ref.watch(toolServiceProvider);
  await service.refreshUnlocks();
  return service.tools();
});

/// Something new in the Tools tab (a dot on its icon).
final newToolsProvider = Provider<int>(
  (ref) => ref.watch(toolsProvider).value?.where((t) => t.isNew).length ?? 0,
);

final competitorServiceProvider = Provider<CompetitorService>(
  (ref) => CompetitorService(ref.watch(appDatabaseProvider)),
);

final _competitorTick = StreamProvider<int>((ref) {
  var tick = 0;
  return ref.watch(competitorServiceProvider).watchChanges().map((_) => ++tick);
});

final competitorsProvider = FutureProvider.family<List<Competitor>, String>((
  ref,
  projectId,
) {
  ref.watch(_competitorTick);
  return ref.watch(competitorServiceProvider).competitorsOf(projectId);
});
