import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../quest/presentation/journey_providers.dart';
import '../application/project_synthesis.dart';

final synthesisServiceProvider = Provider<ProjectSynthesisService>(
  (ref) => ProjectSynthesisService(ref.watch(appDatabaseProvider)),
);

final _synthesisTick = StreamProvider<int>((ref) {
  var tick = 0;
  return ref.watch(synthesisServiceProvider).watchChanges().map((_) => ++tick);
});

/// The active project's work, read again whenever it changes. Null when
/// there is no project yet.
final synthesisProvider = FutureProvider<ProjectSynthesis?>((ref) async {
  ref.watch(_synthesisTick);
  final project = await ref.watch(activeProjectProvider.future);
  if (project == null) return null;
  return ref.watch(synthesisServiceProvider).of(project.id);
});
