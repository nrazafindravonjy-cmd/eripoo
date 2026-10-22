import 'package:drift/drift.dart';

import '../../data/local/app_database.dart';
import '../../data/local/entity_types.dart';

/// Reads and writes any synced entity as JSON, generically over the Drift
/// tables. Writes here bypass repositories on purpose: applying a remote
/// version must not mark it as a new local change.
class EntityRegistry {
  EntityRegistry(this._db)
    : _tables = {
        EntityTypes.profile: _db.userProfiles,
        EntityTypes.fact: _db.facts,
        EntityTypes.project: _db.projects,
        EntityTypes.projectSection: _db.projectSections,
        EntityTypes.projectRevision: _db.projectRevisions,
        EntityTypes.stepProgress: _db.stepProgressEntries,
        EntityTypes.answer: _db.answers,
        EntityTypes.missionInstance: _db.missionInstances,
        EntityTypes.hypothesis: _db.hypotheses,
        EntityTypes.experiment: _db.experiments,
        EntityTypes.experimentHypothesis: _db.experimentHypotheses,
        EntityTypes.result: _db.results,
        EntityTypes.evidence: _db.evidences,
        EntityTypes.conclusion: _db.conclusions,
        EntityTypes.decision: _db.decisions,
        EntityTypes.observation: _db.observations,
        EntityTypes.interview: _db.interviews,
        EntityTypes.media: _db.mediaItems,
        EntityTypes.toolUnlock: _db.toolUnlocks,
        EntityTypes.competitor: _db.competitors,
        EntityTypes.financeItem: _db.financeItems,
        EntityTypes.financePlan: _db.financePlans,
        EntityTypes.conflictCopy: _db.conflictCopies,
      };

  final AppDatabase _db;
  final Map<String, TableInfo<Table, Object?>> _tables;

  /// Current version of the payload format inside envelopes.
  static const schemaVersion = 1;

  bool supports(String entityType) => _tables.containsKey(entityType);

  TableInfo<Table, Object?> _table(String entityType) =>
      _tables[entityType] ??
      (throw ArgumentError.value(entityType, 'entityType'));

  GeneratedColumn<String> _idColumn(TableInfo<Table, Object?> table) =>
      table.columnsByName['id']! as GeneratedColumn<String>;

  Future<Map<String, Object?>?> read(String entityType, String id) async {
    final table = _table(entityType);
    final row = await (_db.select(
      table,
    )..where((_) => _idColumn(table).equals(id))).getSingleOrNull();
    return row == null ? null : (row as DataClass).toJson();
  }

  Future<void> write(String entityType, Map<String, Object?> json) async {
    final table = _table(entityType);
    final row = table.map(_toSqlRow(table, json));
    // Explicit nulls: a field cleared on another phone (a restore from the
    // trash, an emptied note) must be cleared here too. Inserting the data
    // class itself would treat null as "unchanged"; its companion built
    // with nullToAbsent = false keeps them. (Generated per table, hence
    // the dynamic call.)
    // ignore: avoid_dynamic_calls
    final companion =
        (row as dynamic).toCompanion(false) as Insertable<Object?>;
    await _db.into(table).insertOnConflictUpdate(companion);
  }

  Future<void> delete(String entityType, String id) async {
    final table = _table(entityType);
    await (_db.delete(table)..where((_) => _idColumn(table).equals(id))).go();
  }

  /// Converts the camelCase JSON of a data class to the SQL row map that
  /// [TableInfo.map] expects.
  static Map<String, Object?> _toSqlRow(
    TableInfo<Table, Object?> table,
    Map<String, Object?> json,
  ) {
    final row = <String, Object?>{};
    for (final column in table.$columns) {
      final key = _camel(column.name);
      if (json.containsKey(key)) row[column.name] = json[key];
    }
    return row;
  }

  static String _camel(String snake) {
    final parts = snake.split('_');
    return parts.first +
        parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
  }
}
