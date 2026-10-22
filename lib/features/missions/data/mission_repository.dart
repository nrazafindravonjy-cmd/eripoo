import 'package:drift/drift.dart';

import '../../../core/ids/ids.dart';
import '../../../core/time/clock.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/entity_types.dart';
import '../../../data/local/sync_tracker.dart';
import '../domain/mission_state.dart';

/// Mission instances: one per mission template, deterministic id.
class MissionRepository {
  MissionRepository(this._db, {this._clock = systemClock})
    : _sync = SyncTracker(_db);

  final AppDatabase _db;
  final Clock _clock;
  final SyncTracker _sync;

  static String idOf(String templateId) => Ids.forKey('mission:$templateId');

  // Stored as the enum name, like step statuses.
  static String _token(MissionStatus s) => s.name;
  static MissionStatus _status(String name) =>
      MissionStatus.values.byName(name);

  static DateTime? _time(int? ms) =>
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

  MissionInstance _toDomain(MissionInstanceRow r) => MissionInstance(
    templateId: r.templateId,
    status: _status(r.status),
    acceptedAt: _time(r.acceptedAt),
    submittedAt: _time(r.submittedAt),
    completedAt: _time(r.completedAt),
    reflection: r.reflection,
  );

  Future<MissionInstance?> get(String templateId) async {
    final row =
        await (_db.select(_db.missionInstances)..where(
              (t) => t.id.equals(idOf(templateId)) & t.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  Future<List<MissionInstance>> all() async => [
    for (final r in await (_db.select(
      _db.missionInstances,
    )..where((t) => t.deletedAt.isNull())).get())
      _toDomain(r),
  ];

  Stream<List<MissionInstance>> watchAll() =>
      (_db.select(_db.missionInstances)..where((t) => t.deletedAt.isNull()))
          .watch()
          .map((rows) => [for (final r in rows) _toDomain(r)]);

  /// Moves the mission to [to], enforcing the life cycle. Creates the
  /// instance on first acceptance.
  Future<void> move(
    String templateId,
    MissionStatus to, {
    String? reflection,
  }) async {
    final id = idOf(templateId);
    final now = _clock().millisecondsSinceEpoch;
    await _db.transaction(() async {
      final row = await (_db.select(
        _db.missionInstances,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      final from = row == null || row.deletedAt != null
          ? MissionStatus.proposed
          : _status(row.status);
      MissionMachine.check(from, to);
      await _db
          .into(_db.missionInstances)
          .insertOnConflictUpdate(
            MissionInstancesCompanion.insert(
              id: id,
              templateId: templateId,
              status: _token(to),
              acceptedAt: Value(
                to == MissionStatus.accepted ? now : row?.acceptedAt,
              ),
              submittedAt: Value(
                to == MissionStatus.submitted ? now : row?.submittedAt,
              ),
              completedAt: Value(
                to == MissionStatus.completed ? now : row?.completedAt,
              ),
              abandonedAt: Value(
                to == MissionStatus.abandoned ? now : row?.abandonedAt,
              ),
              reflection: Value(reflection ?? row?.reflection),
              createdAt: row?.createdAt ?? now,
              updatedAt: now,
            ),
          );
      await _sync.markChanged(EntityTypes.missionInstance, id);
    });
  }
}
