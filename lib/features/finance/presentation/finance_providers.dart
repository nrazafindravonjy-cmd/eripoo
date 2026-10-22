import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../quest/presentation/journey_providers.dart';
import '../application/finance_service.dart';

final financeServiceProvider = Provider<FinanceService>(
  (ref) => FinanceService(ref.watch(appDatabaseProvider)),
);

final _financeTick = StreamProvider<int>((ref) {
  var tick = 0;
  return ref.watch(financeServiceProvider).watchChanges().map((_) => ++tick);
});

/// The money of a project and the calculators' results.
final financeSnapshotProvider = FutureProvider.family<FinanceSnapshot, String>((
  ref,
  projectId,
) {
  ref.watch(_financeTick);
  return ref.watch(financeServiceProvider).snapshot(projectId);
});
