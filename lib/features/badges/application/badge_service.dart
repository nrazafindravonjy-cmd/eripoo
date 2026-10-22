import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../content/content_pack.dart';
import '../../../content/planner.dart';
import '../../../core/time/clock.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/entity_types.dart';
import '../../../data/local/sync_tracker.dart';

/// A badge and whether the user earned it.
class BadgeState {
  const BadgeState({
    required this.badge,
    required this.earnedAt,
    required this.seen,
  });

  final BadgeDefinition badge;
  final DateTime? earnedAt;

  /// The badge was already announced to the user.
  final bool seen;

  bool get earned => earnedAt != null;

  /// Earned, not yet announced: the celebration is due.
  bool get isNew => earned && !seen;
}

/// Badges (CLAUDE.md §21), with the same life as tool unlocks: each rule
/// is evaluated on what the user has done (progress, facts, counted
/// records, never text); an award is stored, synchronised and permanent.
class BadgeService {
  BadgeService(
    this._db,
    this._pack, {
    required this._input,
    this._clock = systemClock,
  }) : _sync = SyncTracker(_db);

  final AppDatabase _db;
  final ContentPack _pack;
  final Future<PlannerInput> Function() _input;
  final Clock _clock;
  final SyncTracker _sync;

  int _now() => _clock().millisecondsSinceEpoch;

  /// Namespace of the UUID v5 of earned badges (fixed forever).
  static const _namespace = '3b8e1c52-7d4a-4f19-b6c0-9e2a5d7f1c84';

  /// The record id of [badgeId]'s award: identical on every phone.
  static String awardIdOf(String badgeId) =>
      const Uuid().v5(_namespace, 'eripoo:badge:$badgeId');

  Future<Map<String, BadgeAwardRow>> _awards() async => {
    for (final r in await (_db.select(
      _db.badgeAwards,
    )..where((t) => t.deletedAt.isNull())).get())
      r.badgeId: r,
  };

  /// Stores the badges whose rule now holds. Returns the ids newly earned
  /// (empty most of the time).
  Future<List<String>> refreshAwards() async {
    final known = await _awards();
    final pending = [
      for (final b in _pack.badges)
        if (!known.containsKey(b.id)) b,
    ];
    if (pending.isEmpty) return const [];
    final input = await _input();
    final newly = [
      for (final b in pending)
        if (evaluateRule(b.earnedWhen, input)) b.id,
    ];
    if (newly.isEmpty) return const [];
    await _db.transaction(() async {
      final now = _now();
      for (final id in newly) {
        await _db
            .into(_db.badgeAwards)
            .insertOnConflictUpdate(
              BadgeAwardsCompanion.insert(
                id: awardIdOf(id),
                badgeId: id,
                unlockedAt: now,
                createdAt: now,
                updatedAt: now,
              ),
            );
        await _sync.markChanged(EntityTypes.badgeAward, awardIdOf(id));
      }
    });
    return newly;
  }

  /// Every badge of the pack, in content order.
  Future<List<BadgeState>> badges() async {
    final awards = await _awards();
    return [
      for (final b in _pack.badges)
        BadgeState(
          badge: b,
          earnedAt: switch (awards[b.id]) {
            final a? => DateTime.fromMillisecondsSinceEpoch(
              a.unlockedAt,
              isUtc: true,
            ),
            null => null,
          },
          seen: awards[b.id]?.seenAt != null,
        ),
    ];
  }

  /// The award of [ids] was announced (or the user does not want
  /// celebrations): not announced again, on any device.
  Future<void> markSeen(Iterable<String> ids) => _db.transaction(() async {
    final now = _now();
    for (final id in ids) {
      final count =
          await (_db.update(
            _db.badgeAwards,
          )..where((t) => t.badgeId.equals(id) & t.seenAt.isNull())).write(
            BadgeAwardsCompanion(seenAt: Value(now), updatedAt: Value(now)),
          );
      if (count > 0) {
        await _sync.markChanged(EntityTypes.badgeAward, awardIdOf(id));
      }
    }
  });

  /// Ticks when anything a rule can read, or an award, changes.
  Stream<void> watchChanges() => _db.tableUpdates(
    TableUpdateQuery.onAllTables([
      _db.badgeAwards,
      _db.stepProgressEntries,
      _db.facts,
      _db.missionInstances,
      _db.hypotheses,
      _db.experiments,
      _db.evidences,
      _db.observations,
      _db.interviews,
      _db.competitors,
      _db.financeItems,
    ]),
  );
}
