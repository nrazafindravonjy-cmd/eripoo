import 'package:drift/drift.dart';

import '../../../core/ids/ids.dart';
import '../../../core/time/clock.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/entity_types.dart';
import '../../../data/local/sync_tracker.dart';
import '../domain/step_progress.dart';

/// Progress of quest steps (deterministic id per step).
class ProgressRepository {
  ProgressRepository(this._db, {this._clock = systemClock})
    : _sync = SyncTracker(_db);

  final AppDatabase _db;
  final Clock _clock;
  final SyncTracker _sync;

  static DateTime? _time(int? ms) =>
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

  Future<void> setStatus(
    String questId,
    String stepId,
    StepStatus status,
  ) async {
    final id = Ids.forKey('step:$stepId');
    final now = _clock().millisecondsSinceEpoch;
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.stepProgressEntries,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      final startedAt =
          existing?.startedAt ??
          (status.rank >= StepStatus.inProgress.rank ? now : null);
      final completedAt =
          status == StepStatus.completed || status == StepStatus.fastTracked
          ? (existing?.completedAt ?? now)
          : existing?.completedAt;
      await _db
          .into(_db.stepProgressEntries)
          .insertOnConflictUpdate(
            StepProgressEntriesCompanion.insert(
              id: id,
              questId: questId,
              stepId: stepId,
              status: status.name,
              startedAt: Value(startedAt),
              completedAt: Value(completedAt),
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
            ),
          );
      await _sync.markChanged(EntityTypes.stepProgress, id);
    });
  }

  Future<StepProgress?> get(String stepId) async {
    final row = await (_db.select(
      _db.stepProgressEntries,
    )..where((t) => t.id.equals(Ids.forKey('step:$stepId')))).getSingleOrNull();
    if (row == null) return null;
    return StepProgress(
      questId: row.questId,
      stepId: row.stepId,
      status: StepStatus.values.byName(row.status),
      startedAt: _time(row.startedAt),
      completedAt: _time(row.completedAt),
    );
  }
}
