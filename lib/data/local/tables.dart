import 'package:drift/drift.dart';

// Local tables (docs/DATA_MODEL.md §3). Synced business tables carry only
// id and timestamps; sync state lives in [SyncMetaEntries]. Times are UTC
// milliseconds since epoch. No SQL foreign keys between synced tables: a
// child may arrive from another device before its parent
// (docs/OFFLINE_SYNC.md §5).

/// Single user profile (deterministic id).
@DataClassName('UserProfileRow')
class UserProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text().nullable()();
  IntColumn get birthYear => integer().nullable()();
  TextColumn get ageBracket => text().nullable()();
  TextColumn get jurisdictionCode => text().withDefault(const Constant('MG'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Typed facts from the diagnostic and rules (never free text).
@DataClassName('FactRow')
class Facts extends Table {
  TextColumn get id => text()();
  TextColumn get factKey => text().unique()();
  TextColumn get valueJson => text()();
  TextColumn get source => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ProjectRow')
class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get maturityStage => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One row per (project, section) — deterministic id.
@DataClassName('ProjectSectionRow')
class ProjectSections extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get sectionKey => text()();
  TextColumn get fieldsJson => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Append-only history of tracked fields.
@DataClassName('ProjectRevisionRow')
class ProjectRevisions extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get sectionKey => text()();
  TextColumn get fieldKey => text()();
  TextColumn get previousValue => text().nullable()();
  TextColumn get newValue => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Progress of one step of the quest (deterministic id).
@DataClassName('StepProgressRow')
class StepProgressEntries extends Table {
  TextColumn get id => text()();
  TextColumn get questId => text()();
  TextColumn get stepId => text()();
  TextColumn get status => text()();
  IntColumn get startedAt => integer().nullable()();
  IntColumn get completedAt => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Versions set aside by conflict resolution (synced, append-only).
@DataClassName('ConflictCopyRow')
class ConflictCopies extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get payloadJson => text()();
  TextColumn get fromDeviceId => text().nullable()();
  IntColumn get resolvedAt => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Sync state of every synced entity (local only).
@DataClassName('SyncMetaRow')
class SyncMetaEntries extends Table {
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();

  /// Last server version known for this entity; null = never sent.
  IntColumn get baseVersion => integer().nullable()();

  /// Non-null = local change waiting to be sent.
  TextColumn get changeId => text().nullable()();

  /// Last change id sent (recognises our own echo after a lost response).
  TextColumn get pushedChangeId => text().nullable()();
  TextColumn get lastError => text().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get nextAttemptAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {entityType, entityId};
}
