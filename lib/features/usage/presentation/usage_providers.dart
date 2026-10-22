import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/backend/backend.dart';
import '../../account/presentation/account_providers.dart';
import '../../quest/presentation/journey_providers.dart';
import '../application/usage_counter.dart';
import '../data/supabase_usage_sink.dart';
import '../domain/usage_event.dart';

final usageCounterProvider = Provider<UsageCounter>(
  (ref) => UsageCounter(ref.watch(appDatabaseProvider)),
);

/// Counts [event] and tries to send what is pending. Never throws, never
/// blocks the screen: statistics are worth less than any user action.
Future<void> countUsage(Ref ref, UsageEvent event) async {
  try {
    final counter = ref.read(usageCounterProvider);
    await counter.record(event);
    final backend = await ref.read(accountBackendProvider.future);
    if (backend is Backend) {
      await counter.flush(supabaseUsageSink(backend.client));
    }
  } on Object {
    // Offline or refused: kept (or dropped) quietly.
  }
}

/// `ref.read(usageRecorderProvider)(UsageEvent.pdfExported)` from widgets.
final usageRecorderProvider = Provider<Future<void> Function(UsageEvent)>(
  (ref) =>
      (event) => countUsage(ref, event),
);
