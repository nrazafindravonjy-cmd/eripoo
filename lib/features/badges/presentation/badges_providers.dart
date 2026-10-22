import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../quest/presentation/journey_providers.dart';
import '../application/badge_service.dart';

final badgeServiceProvider = Provider<BadgeService>((ref) {
  final journey = ref.watch(journeyServiceProvider);
  return BadgeService(
    ref.watch(appDatabaseProvider),
    ref.watch(contentPackProvider),
    input: journey.input,
  );
});

final _badgeTick = StreamProvider<int>((ref) {
  var tick = 0;
  return ref.watch(badgeServiceProvider).watchChanges().map((_) => ++tick);
});

/// Every badge and its state; awards are evaluated each time what the
/// rules read changes (so a badge is earned wherever the user is).
final badgesProvider = FutureProvider<List<BadgeState>>((ref) async {
  ref.watch(_badgeTick);
  final service = ref.watch(badgeServiceProvider);
  await service.refreshAwards();
  return service.badges();
});
