import 'package:drift/drift.dart';

import 'tables.dart';

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
/// Not frozen until the first release with real users, but every change
/// still comes with a migration (development databases keep working).
@DriftDatabase(
  tables: [
    LocalKeyValues,
    UserProfiles,
    Facts,
    Projects,
    ProjectSections,
    ProjectRevisions,
    StepProgressEntries,
    Answers,
    MissionInstances,
    ConflictCopies,
    SyncMetaEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Phase 3: answers, missions, deferred steps.
        await m.createTable(answers);
        await m.createTable(missionInstances);
        await m.addColumn(
          stepProgressEntries,
          stepProgressEntries.deferredUntil,
        );
      }
    },
  );

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
