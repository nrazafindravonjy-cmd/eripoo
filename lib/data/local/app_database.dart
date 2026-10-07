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
    Hypotheses,
    Experiments,
    ExperimentHypotheses,
    Results,
    Evidences,
    Conclusions,
    Decisions,
    Observations,
    Interviews,
    MediaItems,
    MediaUploads,
    ConflictCopies,
    SyncMetaEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 5;

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
      if (from < 3) {
        // Phase 4: hypotheses and their tests, field notes, media.
        for (final TableInfo<Table, Object?> table in [
          hypotheses,
          experiments,
          experimentHypotheses,
          results,
          evidences,
          conclusions,
          decisions,
          observations,
          interviews,
          mediaItems,
        ]) {
          await m.createTable(table);
        }
      }
      if (from < 4) {
        // Phase 5: media files to send (local only). Photos taken before
        // are queued too: none of them is on the server yet.
        await m.createTable(mediaUploads);
        await customStatement(
          'INSERT INTO media_uploads (media_id, attempts) '
          'SELECT id, 0 FROM media_items WHERE deleted_at IS NULL',
        );
      }
      if (from < 5) {
        // Phase 5: "delete forever" from the trash.
        await m.addColumn(syncMetaEntries, syncMetaEntries.purgeRequested);
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

  Future<void> deleteValue(String key) =>
      (delete(localKeyValues)..where((t) => t.key.equals(key))).go();
}
