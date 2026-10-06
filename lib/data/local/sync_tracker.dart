import 'package:drift/drift.dart';

import '../../core/ids/ids.dart';
import 'app_database.dart';

/// Marks entities as changed in `sync_meta`. Must be called inside the
/// same Drift transaction as the business write, so a change can never be
/// saved without being scheduled for synchronisation (and vice versa).
class SyncTracker {
  SyncTracker(this._db);

  final AppDatabase _db;

  Future<void> markChanged(String entityType, String entityId) async {
    final changeId = Ids.random();
    final existing =
        await (_db.select(_db.syncMetaEntries)..where(
              (t) =>
                  t.entityType.equals(entityType) & t.entityId.equals(entityId),
            ))
            .getSingleOrNull();
    if (existing == null) {
      await _db
          .into(_db.syncMetaEntries)
          .insert(
            SyncMetaEntriesCompanion.insert(
              entityType: entityType,
              entityId: entityId,
              changeId: Value(changeId),
            ),
          );
    } else {
      await (_db.update(_db.syncMetaEntries)..where(
            (t) =>
                t.entityType.equals(entityType) & t.entityId.equals(entityId),
          ))
          .write(
            SyncMetaEntriesCompanion(
              changeId: Value(changeId),
              lastError: const Value(null),
              attempts: const Value(0),
              nextAttemptAt: const Value(null),
            ),
          );
    }
  }

  /// Number of local changes waiting to be sent.
  Stream<int> watchPendingCount() {
    final count = _db.syncMetaEntries.entityId.count();
    return (_db.selectOnly(_db.syncMetaEntries)
          ..addColumns([count])
          ..where(_db.syncMetaEntries.changeId.isNotNull()))
        .map((row) => row.read(count) ?? 0)
        .watchSingle();
  }
}
