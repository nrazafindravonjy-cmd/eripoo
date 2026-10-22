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

  /// "Skip for now": when the step comes back (schema v2).
  IntColumn get deferredUntil => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Answer to one question block of a step (schema v2). One per block:
/// deterministic id, so two devices answering the same question meet.
@DataClassName('AnswerRow')
class Answers extends Table {
  TextColumn get id => text()();
  TextColumn get questId => text()();
  TextColumn get stepId => text()();
  TextColumn get blockId => text()();

  /// `text`, `choice`, `multi_choice`, `number`, `money`, `unknown`, or
  /// `voice` (value: the media id of the encrypted recording, Phase 9).
  TextColumn get answerType => text()();
  TextColumn get valueJson => text().nullable()();

  /// Highest help level used (0 none, 1–2 rephrasing, 3 example, 4 hints).
  IntColumn get helpUsed => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A mission accepted from the content (schema v2).
@DataClassName('MissionInstanceRow')
class MissionInstances extends Table {
  TextColumn get id => text()();
  TextColumn get templateId => text()();
  TextColumn get status => text()();
  IntColumn get acceptedAt => integer().nullable()();
  IntColumn get submittedAt => integer().nullable()();
  IntColumn get completedAt => integer().nullable()();
  IntColumn get abandonedAt => integer().nullable()();

  /// The user's account of what they did (private, encrypted when synced).
  TextColumn get reflection => text().nullable()();
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

  /// "Delete forever" asked here: the server gets a tombstone without
  /// content; the local row is removed only once the server confirmed
  /// (docs/OFFLINE_SYNC.md §7).
  BoolColumn get purgeRequested =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {entityType, entityId};
}

// ---- Schema v3 (Phase 4): hypothesis → experiment → result → evidence →
// conclusion → decision (docs/DATA_MODEL.md §3.4), field notes, media.

@DataClassName('HypothesisRow')
class Hypotheses extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get statement => text()();

  /// `problem`, `customer`, `solution`, `price`, `channel`, `other`.
  TextColumn get category => text()();

  /// 1 (nice to know) to 3 (the project depends on it).
  IntColumn get importance => integer().withDefault(const Constant(2))();

  /// 1–5, before any test.
  IntColumn get confidenceBefore => integer().nullable()();

  /// See HypothesisStatus (snake_case).
  TextColumn get status => text()();

  /// Previous version, when this one was written after a test.
  TextColumn get parentHypothesisId => text().nullable()();

  /// Journey step it came from ("go back" reopens it).
  TextColumn get sourceStepId => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ExperimentRow')
class Experiments extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get method => text()();
  TextColumn get plan => text()();

  /// Defined before the test; locked when it starts.
  TextColumn get successCriterion => text().nullable()();
  IntColumn get criterionLockedAt => integer().nullable()();
  IntColumn get sampleTarget => integer().nullable()();
  IntColumn get startedAt => integer().nullable()();
  IntColumn get endedAt => integer().nullable()();
  TextColumn get status => text()();
  TextColumn get missionInstanceId => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Which hypotheses an experiment tests (deterministic id per pair).
@DataClassName('ExperimentHypothesisRow')
class ExperimentHypotheses extends Table {
  TextColumn get id => text()();
  TextColumn get experimentId => text()();
  TextColumn get hypothesisId => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ResultRow')
class Results extends Table {
  TextColumn get id => text()();
  TextColumn get experimentId => text()();
  TextColumn get summary => text()();

  /// "7 out of 10": both or neither.
  IntColumn get metricYes => integer().nullable()();
  IntColumn get metricTotal => integer().nullable()();
  IntColumn get recordedAt => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A piece of evidence attached to any subject (polymorphic).
@DataClassName('EvidenceRow')
class Evidences extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();

  /// See EvidenceSubject (snake_case).
  TextColumn get subjectType => text()();
  TextColumn get subjectId => text()();

  /// `note`, `photo`, `link`, `number`, `sale`.
  TextColumn get kind => text()();
  TextColumn get body => text().nullable()();
  TextColumn get mediaId => text().nullable()();

  /// A number (kind `number`).
  RealColumn get numberValue => real().nullable()();

  /// A sale in ariary (kind `sale`).
  IntColumn get amountMga => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ConclusionRow')
class Conclusions extends Table {
  TextColumn get id => text()();
  TextColumn get hypothesisId => text()();
  TextColumn get experimentId => text().nullable()();

  /// What the user now thinks.
  TextColumn get statement => text()();

  /// The status reached (validated, invalidated, inconclusive).
  TextColumn get outcome => text()();
  IntColumn get confidenceAfter => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Decision journal (append-only).
@DataClassName('DecisionRow')
class Decisions extends Table {
  TextColumn get id => text()();
  TextColumn get hypothesisId => text()();
  TextColumn get experimentId => text().nullable()();

  /// `continue`, `modify`, `test_more`, `abandon`, `go_back`.
  TextColumn get decision => text()();
  TextColumn get rationale => text()();

  /// The new version created by `modify`.
  TextColumn get newHypothesisId => text().nullable()();
  IntColumn get decidedAt => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Something seen in the field (photos are attached as evidence).
@DataClassName('ObservationRow')
class Observations extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get description => text()();

  /// Where and when, in the user's words.
  TextColumn get context => text().nullable()();
  TextColumn get supposedProblem => text().nullable()();
  IntColumn get observedAt => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A conversation with a potential customer: pseudonym only, written
/// notes only (no recording of other people — legal advice P6 pending).
@DataClassName('InterviewRow')
class Interviews extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get intervieweeAlias => text()();
  TextColumn get notes => text()();
  TextColumn get conclusion => text().nullable()();
  IntColumn get heldAt => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// An encrypted file of the app's private directory (docs/SECURITY.md
/// §4.7). The path is derived from the id; it is never stored.
@DataClassName('MediaRow')
class MediaItems extends Table {
  TextColumn get id => text()();

  /// `photo`, or `audio` (spoken answers, Phase 9).
  TextColumn get kind => text()();
  TextColumn get mime => text()();

  /// Size of the plain file (≤ 10 MiB, D15).
  IntColumn get sizeBytes => integer()();

  /// BLAKE2b-256 of the plain file, hex (libsodium `crypto_generichash`):
  /// identifies the content without decrypting it again.
  TextColumn get contentHash => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Local only, never synchronised: which media files this phone still has
/// to send to the server (docs/OFFLINE_SYNC.md §9). A row is added with
/// each photo taken here; files received from the server are already
/// there and get no row.
class MediaUploads extends Table {
  TextColumn get mediaId => text()();

  /// Null while waiting; set once the server has the file.
  IntColumn get uploadedAt => integer().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Set when the server refused the file (kept locally, retried later).
  IntColumn get nextAttemptAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {mediaId};
}

// ---- Schema v6 (Phase 6): tools.

/// A tool unlocked on this account (synced). Never re-locked: concurrent
/// versions keep the earliest unlock (docs/OFFLINE_SYNC.md §6).
@DataClassName('ToolUnlockRow')
class ToolUnlocks extends Table {
  /// UUID v5 of [toolId]: the same on every phone, so two phones that
  /// unlock a tool offline produce one record, not two.
  TextColumn get id => text()();

  /// The tool id from the content pack (`tool.interview_guide`).
  TextColumn get toolId => text().unique()();
  IntColumn get unlockedAt => integer()();

  /// When the unlock was shown to the user (celebration), once.
  IntColumn get seenAt => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Badges earned (CLAUDE.md §21), same life as [ToolUnlocks]: stored,
/// synchronised, never taken back; concurrent versions keep the earliest.
@DataClassName('BadgeAwardRow')
class BadgeAwards extends Table {
  /// UUID v5 of [badgeId]: one record even if two phones award it offline.
  TextColumn get id => text()();

  /// The badge id from the content pack (`badge.truth_seeker`).
  TextColumn get badgeId => text().unique()();
  IntColumn get unlockedAt => integer()();

  /// When the badge was shown to the user (celebration), once.
  IntColumn get seenAt => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// What people already use instead of the project (competitor analysis):
/// the user's own observations, no personal data.
@DataClassName('CompetitorRow')
class Competitors extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get name => text()();

  /// `direct`, `indirect` or `alternative` (doing it oneself, doing nothing).
  TextColumn get kind => text()();
  TextColumn get offer => text().nullable()();

  /// A price observed, in ariary.
  IntColumn get priceMga => integer().nullable()();
  TextColumn get strengths => text().nullable()();
  TextColumn get weaknesses => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Money of a project (Phase 7, CLAUDE.md §17): what one unit costs, the
/// costs of each month, what must be bought before starting, and the money
/// found. Amounts in whole ariary.
@DataClassName('FinanceItemRow')
class FinanceItems extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text()();

  /// `variable_cost` (per unit sold), `fixed_cost` (per month),
  /// `investment` (once, before starting) or `funding` (money found).
  TextColumn get kind => text()();

  /// For `funding` only: `own`, `family`, `microfinance`, `bank`,
  /// `investor`, `grant` or `other`.
  TextColumn get source => text().nullable()();
  TextColumn get label => text()();
  IntColumn get amountMga => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The price chosen and the sales expected, one per project (UUID v5 of
/// the project id): what the margin, break-even and cash plan use.
@DataClassName('FinancePlanRow')
class FinancePlans extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().unique()();
  IntColumn get priceMga => integer().nullable()();

  /// Units expected in the first month and in the twelfth.
  IntColumn get volumeFirst => integer().nullable()();
  IntColumn get volumeLast => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
