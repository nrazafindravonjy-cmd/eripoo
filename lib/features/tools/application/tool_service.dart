import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../content/content_pack.dart';
import '../../../content/planner.dart';
import '../../../core/time/clock.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/entity_types.dart';
import '../../../data/local/sync_tracker.dart';

/// A tool and where the user stands with it.
class ToolState {
  const ToolState({
    required this.tool,
    required this.unlockedAt,
    required this.seen,
  });

  final ToolDefinition tool;
  final DateTime? unlockedAt;

  /// The unlock was already announced to the user.
  final bool seen;

  bool get unlocked => unlockedAt != null;

  /// Unlocked and buildable in this version: can be opened.
  bool get usable => unlocked && tool.implemented;

  /// Unlocked, usable, not yet announced: the celebration is due.
  bool get isNew => usable && !seen;
}

/// Progressive unlocking of the tools (CLAUDE.md §20): each tool's rule is
/// evaluated on what the user has done (the journey's own rule context:
/// progress, facts, counted records — never text). An unlock is stored,
/// synchronised and permanent: undoing the work later does not re-lock.
class ToolService {
  ToolService(
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

  /// Namespace of the UUID v5 of unlocked tools (fixed forever).
  static const _namespace = 'f0d6c1e2-5b0a-4c0e-9a51-6d1f0a3b7e21';

  /// The record id of [toolId]'s unlock: identical on every phone.
  static String unlockIdOf(String toolId) =>
      const Uuid().v5(_namespace, 'eripoo:tool:$toolId');

  Future<Map<String, ToolUnlockRow>> _unlocks() async => {
    for (final r in await (_db.select(
      _db.toolUnlocks,
    )..where((t) => t.deletedAt.isNull())).get())
      r.toolId: r,
  };

  /// Stores the tools whose rule now holds. Returns the ids newly
  /// unlocked (empty most of the time).
  Future<List<String>> refreshUnlocks() async {
    final known = await _unlocks();
    final pending = [
      for (final t in _pack.tools)
        if (!known.containsKey(t.id)) t,
    ];
    if (pending.isEmpty) return const [];
    final input = await _input();
    final newly = [
      for (final t in pending)
        if (t.unlock == null || evaluateRule(t.unlock!, input)) t.id,
    ];
    if (newly.isEmpty) return const [];
    await _db.transaction(() async {
      final now = _now();
      for (final id in newly) {
        await _db
            .into(_db.toolUnlocks)
            .insertOnConflictUpdate(
              ToolUnlocksCompanion.insert(
                id: unlockIdOf(id),
                toolId: id,
                unlockedAt: now,
                createdAt: now,
                updatedAt: now,
              ),
            );
        await _sync.markChanged(EntityTypes.toolUnlock, unlockIdOf(id));
      }
    });
    return newly;
  }

  /// Every tool of the pack, in content order.
  Future<List<ToolState>> tools() async {
    final unlocks = await _unlocks();
    return [
      for (final t in _pack.tools)
        ToolState(
          tool: t,
          unlockedAt: switch (unlocks[t.id]) {
            final u? => DateTime.fromMillisecondsSinceEpoch(
              u.unlockedAt,
              isUtc: true,
            ),
            null => null,
          },
          seen: unlocks[t.id]?.seenAt != null,
        ),
    ];
  }

  /// The unlock of [ids] was announced (or the user does not want
  /// celebrations): not announced again, on any device.
  Future<void> markSeen(Iterable<String> ids) => _db.transaction(() async {
    final now = _now();
    for (final id in ids) {
      final count =
          await (_db.update(
            _db.toolUnlocks,
          )..where((t) => t.toolId.equals(id) & t.seenAt.isNull())).write(
            ToolUnlocksCompanion(seenAt: Value(now), updatedAt: Value(now)),
          );
      if (count > 0) {
        await _sync.markChanged(EntityTypes.toolUnlock, unlockIdOf(id));
      }
    }
  });

  /// Ticks when anything a rule can read, or an unlock, changes.
  Stream<void> watchChanges() => _db.tableUpdates(
    TableUpdateQuery.onAllTables([
      _db.toolUnlocks,
      _db.stepProgressEntries,
      _db.facts,
      _db.missionInstances,
      _db.hypotheses,
      _db.experiments,
      _db.evidences,
      _db.observations,
      _db.interviews,
      _db.competitors,
    ]),
  );
}
