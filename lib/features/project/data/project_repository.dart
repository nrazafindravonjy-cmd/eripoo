import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/ids/ids.dart';
import '../../../core/time/clock.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/entity_types.dart';
import '../../../data/local/sync_tracker.dart';
import '../domain/project.dart';

/// Local projects, sections and their history. Every write marks the
/// entity for synchronisation in the same transaction.
class ProjectRepository {
  ProjectRepository(this._db, {this._clock = systemClock})
    : _sync = SyncTracker(_db);

  final AppDatabase _db;
  final Clock _clock;
  final SyncTracker _sync;

  int _now() => _clock().millisecondsSinceEpoch;

  static DateTime _time(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

  static Project _toDomain(ProjectRow row) => Project(
    id: row.id,
    title: row.title,
    maturityStage: MaturityStage.values.byName(row.maturityStage),
    createdAt: _time(row.createdAt),
    updatedAt: _time(row.updatedAt),
    deletedAt: row.deletedAt == null ? null : _time(row.deletedAt!),
  );

  Future<Project> create(String title) async {
    final validTitle = ProjectRules.validateTitle(title);
    final id = Ids.newId();
    final now = _now();
    await _db.transaction(() async {
      await _db
          .into(_db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: id,
              title: validTitle,
              maturityStage: MaturityStage.exploration.name,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _sync.markChanged(EntityTypes.project, id);
    });
    return (await get(id))!;
  }

  Future<Project?> get(String id) async {
    final row = await (_db.select(
      _db.projects,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  SimpleSelectStatement<$ProjectsTable, ProjectRow> _activeQuery() =>
      _db.select(_db.projects)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);

  /// Projects not in the trash, oldest first.
  Future<List<Project>> active() async =>
      (await _activeQuery().get()).map(_toDomain).toList();

  /// Same, updated on every change.
  Stream<List<Project>> watchActive() =>
      _activeQuery().watch().map((rows) => rows.map(_toDomain).toList());

  Future<void> rename(String id, String title) => _update(
    id,
    ProjectsCompanion(title: Value(ProjectRules.validateTitle(title))),
  );

  Future<void> setMaturity(String id, MaturityStage stage) =>
      _update(id, ProjectsCompanion(maturityStage: Value(stage.name)));

  /// Moves the project to the trash. Content is kept (restorable).
  Future<void> moveToTrash(String id) =>
      _update(id, ProjectsCompanion(deletedAt: Value(_now())));

  Future<void> restore(String id) =>
      _update(id, const ProjectsCompanion(deletedAt: Value(null)));

  Future<void> _update(String id, ProjectsCompanion changes) =>
      _db.transaction(() async {
        final count =
            await (_db.update(_db.projects)..where((t) => t.id.equals(id)))
                .write(changes.copyWith(updatedAt: Value(_now())));
        if (count == 0) throw StateError('Unknown project');
        await _sync.markChanged(EntityTypes.project, id);
      });

  /// Writes a section's fields. Each field listed in [trackedFields] whose
  /// value changes is recorded in the history (append-only).
  Future<void> saveSection({
    required String projectId,
    required String sectionKey,
    required Map<String, Object?> fields,
    Set<String> trackedFields = const {},
  }) async {
    final id = Ids.forKey('section:$projectId:$sectionKey');
    final now = _now();
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.projectSections,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      final previous = existing == null
          ? const <String, Object?>{}
          : jsonDecode(existing.fieldsJson) as Map<String, Object?>;

      await _db
          .into(_db.projectSections)
          .insertOnConflictUpdate(
            ProjectSectionsCompanion.insert(
              id: id,
              projectId: projectId,
              sectionKey: sectionKey,
              fieldsJson: jsonEncode(fields),
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
            ),
          );
      await _sync.markChanged(EntityTypes.projectSection, id);

      for (final field in trackedFields) {
        final before = previous[field];
        final after = fields[field];
        if (before == after) continue;
        final revisionId = Ids.newId();
        await _db
            .into(_db.projectRevisions)
            .insert(
              ProjectRevisionsCompanion.insert(
                id: revisionId,
                projectId: projectId,
                sectionKey: sectionKey,
                fieldKey: field,
                previousValue: Value(before?.toString()),
                newValue: Value(after?.toString()),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await _sync.markChanged(EntityTypes.projectRevision, revisionId);
      }
    });
  }

  Future<ProjectSection?> section(String projectId, String sectionKey) async {
    final row =
        await (_db.select(_db.projectSections)..where(
              (t) => t.id.equals(Ids.forKey('section:$projectId:$sectionKey')),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return ProjectSection(
      id: row.id,
      projectId: row.projectId,
      sectionKey: row.sectionKey,
      fields: jsonDecode(row.fieldsJson) as Map<String, Object?>,
      updatedAt: _time(row.updatedAt),
    );
  }

  /// Every section of a project, by section key.
  Future<Map<String, ProjectSection>> sections(String projectId) async {
    final rows =
        await (_db.select(_db.projectSections)..where(
              (t) => t.projectId.equals(projectId) & t.deletedAt.isNull(),
            ))
            .get();
    return {
      for (final row in rows)
        row.sectionKey: ProjectSection(
          id: row.id,
          projectId: row.projectId,
          sectionKey: row.sectionKey,
          fields: jsonDecode(row.fieldsJson) as Map<String, Object?>,
          updatedAt: _time(row.updatedAt),
        ),
    };
  }

  /// Fires on any change of sections or their history.
  Stream<void> watchSectionChanges() => _db.tableUpdates(
    TableUpdateQuery.onAllTables([_db.projectSections, _db.projectRevisions]),
  );

  /// History of a project, oldest first.
  Future<List<ProjectRevision>> history(String projectId) async {
    final rows =
        await (_db.select(_db.projectRevisions)
              ..where(
                (t) => t.projectId.equals(projectId) & t.deletedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    return [
      for (final r in rows)
        ProjectRevision(
          sectionKey: r.sectionKey,
          fieldKey: r.fieldKey,
          previousValue: r.previousValue,
          newValue: r.newValue,
          createdAt: _time(r.createdAt),
        ),
    ];
  }
}
