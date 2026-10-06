import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// Small local key/value store for technical state (sync cursor, device
/// id, settings). Never used for user content.
class LocalKeyValues extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// The local database: source of truth of the app (docs/DATA_MODEL.md §3).
///
/// Schema version 1 is **not frozen** until the first release with real
/// users: development databases are disposable.
@DriftDatabase(tables: [LocalKeyValues])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  Future<String?> readValue(String key) async {
    final row = await (select(
      localKeyValues,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> writeValue(String key, String value) => into(localKeyValues)
      .insertOnConflictUpdate(
        LocalKeyValuesCompanion.insert(key: key, value: value),
      );
}
