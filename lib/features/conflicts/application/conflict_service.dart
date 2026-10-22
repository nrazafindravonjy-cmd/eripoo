import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/time/clock.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/entity_types.dart';
import '../../../data/local/sync_tracker.dart';
import '../../../sync/engine/entity_registry.dart';

/// A text that differs between the two versions.
class ConflictDifference {
  const ConflictDifference({required this.current, required this.other});

  /// Null when the field is empty in that version.
  final String? current;
  final String? other;
}

/// A version set aside by synchronisation (docs/OFFLINE_SYNC.md §6): the
/// same element was changed on two phones; the one kept and the other.
class ConflictView {
  const ConflictView({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.setAsideAt,
    required this.differences,
  });

  final String id;
  final String entityType;
  final String entityId;
  final DateTime setAsideAt;

  /// The user's texts that differ; empty when only technical fields do.
  final List<ConflictDifference> differences;
}

/// Lets the user decide between two versions: keep the current one (the
/// copy is marked resolved) or take the other one back (a new change,
/// synchronised like any edit). Nothing is ever deleted: a resolved copy
/// stays in the history.
class ConflictService {
  ConflictService(this._db, {this._clock = systemClock})
    : _registry = EntityRegistry(_db),
      _sync = SyncTracker(_db);

  final AppDatabase _db;
  final Clock _clock;
  final EntityRegistry _registry;
  final SyncTracker _sync;

  int _now() => _clock().millisecondsSinceEpoch;

  /// Fields that are not the user's words (identifiers, dates, states).
  static bool _technical(String key) =>
      key == 'id' ||
      key.endsWith('Id') ||
      key.endsWith('At') ||
      key == 'status' ||
      key == 'kind' ||
      key == 'mime' ||
      key == 'contentHash';

  static String? _text(Object? value) {
    if (value == null) return null;
    final text = value is String ? value : jsonEncode(value);
    return text.trim().isEmpty ? null : text;
  }

  static List<ConflictDifference> _differences(
    Map<String, Object?> current,
    Map<String, Object?> other,
  ) => [
    for (final key in {...current.keys, ...other.keys})
      if (!_technical(key) && _text(current[key]) != _text(other[key]))
        ConflictDifference(
          current: _text(current[key]),
          other: _text(other[key]),
        ),
  ];

  /// Copies still to decide, newest first. Copies whose element no longer
  /// exists here, or of internal entities, are not shown.
  Future<List<ConflictView>> pending() async {
    final rows =
        await (_db.select(_db.conflictCopies)
              ..where((c) => c.resolvedAt.isNull() & c.deletedAt.isNull())
              ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]))
            .get();
    final views = <ConflictView>[];
    for (final row in rows) {
      if (row.entityType == EntityTypes.conflictCopy ||
          !_registry.supports(row.entityType)) {
        continue;
      }
      final current = await _registry.read(row.entityType, row.entityId);
      if (current == null) continue;
      final other = (jsonDecode(row.payloadJson) as Map)
          .cast<String, Object?>();
      views.add(
        ConflictView(
          id: row.id,
          entityType: row.entityType,
          entityId: row.entityId,
          setAsideAt: DateTime.fromMillisecondsSinceEpoch(
            row.createdAt,
            isUtc: true,
          ),
          differences: _differences(current, other),
        ),
      );
    }
    return views;
  }

  /// The current version is the right one.
  Future<void> keepCurrent(String copyId) =>
      _db.transaction(() => _resolve(copyId));

  /// The version set aside is the right one: it becomes the current one
  /// (its identity and creation date are kept).
  Future<void> keepOther(String copyId) => _db.transaction(() async {
    final row = await (_db.select(
      _db.conflictCopies,
    )..where((c) => c.id.equals(copyId))).getSingle();
    final current = await _registry.read(row.entityType, row.entityId);
    if (current == null) return;
    final other = (jsonDecode(row.payloadJson) as Map).cast<String, Object?>();
    await _registry.write(row.entityType, {
      ...current,
      for (final e in other.entries)
        if (e.key != 'id' && e.key != 'createdAt') e.key: e.value,
      'updatedAt': _now(),
    });
    await _sync.markChanged(row.entityType, row.entityId);
    await _resolve(copyId);
  });

  Future<void> _resolve(String copyId) async {
    await (_db.update(
      _db.conflictCopies,
    )..where((c) => c.id.equals(copyId))).write(
      ConflictCopiesCompanion(
        resolvedAt: Value(_now()),
        updatedAt: Value(_now()),
      ),
    );
    await _sync.markChanged(EntityTypes.conflictCopy, copyId);
  }

  /// Ticks when copies or their elements change.
  Stream<void> watchChanges() =>
      _db.tableUpdates(TableUpdateQuery.onAllTables([_db.conflictCopies]));
}
