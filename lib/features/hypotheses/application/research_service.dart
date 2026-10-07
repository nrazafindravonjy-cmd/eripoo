import 'package:drift/drift.dart';

import '../../../core/ids/ids.dart';
import '../../../core/time/clock.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/entity_types.dart';
import '../../../data/local/sync_tracker.dart';
import '../../quest/data/progress_repository.dart';
import '../../quest/domain/step_progress.dart';
import '../domain/research.dart';

/// Hypotheses and their tests (docs/PRODUCT_ARCHITECTURE.md §4): every
/// operation checks the state machines and business rules, then writes
/// and marks for synchronisation in one transaction.
///
/// [questOfStep] finds the quest of a journey step, for the "go back"
/// decision (null: the step is not reopened).
class ResearchService {
  ResearchService(this._db, {this._clock = systemClock, this._questOfStep})
    : _sync = SyncTracker(_db),
      _progress = ProgressRepository(_db, clock: _clock);

  final AppDatabase _db;
  final Clock _clock;
  final SyncTracker _sync;
  final String? Function(String stepId)? _questOfStep;
  final ProgressRepository _progress;

  int _now() => _clock().millisecondsSinceEpoch;

  static DateTime _time(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  static DateTime? _timeOrNull(int? ms) => ms == null ? null : _time(ms);
  static String _token(Enum e) => HypothesisTokens.of(e);
  static T _parse<T extends Enum>(List<T> values, String token) =>
      HypothesisTokens.parse(values, token);

  static Never _fail(GuardFailure failure) => throw GuardViolation(failure);

  static String? _optionalText(String? text, int maxLength) {
    if (text == null || text.trim().isEmpty) return null;
    return HypothesisRules.checkText(text, maxLength);
  }

  // ------------------------------------------------------------ reading

  static Hypothesis _hypothesis(HypothesisRow r) => Hypothesis(
    id: r.id,
    projectId: r.projectId,
    statement: r.statement,
    category: _parse(HypothesisCategory.values, r.category),
    importance: r.importance,
    confidenceBefore: r.confidenceBefore,
    status: _parse(HypothesisStatus.values, r.status),
    parentHypothesisId: r.parentHypothesisId,
    sourceStepId: r.sourceStepId,
    createdAt: _time(r.createdAt),
  );

  Future<Hypothesis?> hypothesis(String id) async {
    final row = await (_db.select(
      _db.hypotheses,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    return row == null ? null : _hypothesis(row);
  }

  Future<Hypothesis> _requireHypothesis(String id) async =>
      await hypothesis(id) ?? _fail(GuardFailure.notFound);

  /// Hypotheses of a project, oldest first.
  Future<List<Hypothesis>> hypothesesOf(String projectId) async {
    final rows =
        await (_db.select(_db.hypotheses)
              ..where(
                (t) => t.projectId.equals(projectId) & t.deletedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    return rows.map(_hypothesis).toList();
  }

  Future<List<String>> _hypothesisIdsOf(String experimentId) async {
    final rows =
        await (_db.select(_db.experimentHypotheses)..where(
              (t) => t.experimentId.equals(experimentId) & t.deletedAt.isNull(),
            ))
            .get();
    return [for (final r in rows) r.hypothesisId];
  }

  Future<Experiment> _experiment(ExperimentRow r) async => Experiment(
    id: r.id,
    projectId: r.projectId,
    method: _parse(ExperimentMethod.values, r.method),
    plan: r.plan,
    successCriterion: r.successCriterion,
    criterionLockedAt: _timeOrNull(r.criterionLockedAt),
    sampleTarget: r.sampleTarget,
    startedAt: _timeOrNull(r.startedAt),
    endedAt: _timeOrNull(r.endedAt),
    status: _parse(ExperimentStatus.values, r.status),
    hypothesisIds: await _hypothesisIdsOf(r.id),
  );

  Future<Experiment?> experiment(String id) async {
    final row = await (_db.select(
      _db.experiments,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    return row == null ? null : _experiment(row);
  }

  Future<Experiment> _requireExperiment(String id) async =>
      await experiment(id) ?? _fail(GuardFailure.notFound);

  /// Experiments testing [hypothesisId], oldest first.
  Future<List<Experiment>> experimentsFor(String hypothesisId) async {
    final links =
        await (_db.select(_db.experimentHypotheses)..where(
              (t) => t.hypothesisId.equals(hypothesisId) & t.deletedAt.isNull(),
            ))
            .get();
    final ids = links.map((l) => l.experimentId).toSet();
    if (ids.isEmpty) return const [];
    final rows =
        await (_db.select(_db.experiments)
              ..where((t) => t.id.isIn(ids) & t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    return [for (final r in rows) await _experiment(r)];
  }

  Future<List<ExperimentResult>> resultsOf(String experimentId) async {
    final rows =
        await (_db.select(_db.results)
              ..where(
                (t) =>
                    t.experimentId.equals(experimentId) & t.deletedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.recordedAt)]))
            .get();
    return [
      for (final r in rows)
        ExperimentResult(
          id: r.id,
          experimentId: r.experimentId,
          summary: r.summary,
          yes: r.metricYes,
          total: r.metricTotal,
          recordedAt: _time(r.recordedAt),
        ),
    ];
  }

  static Evidence _evidence(EvidenceRow r) => Evidence(
    id: r.id,
    projectId: r.projectId,
    subject: _parse(EvidenceSubject.values, r.subjectType),
    subjectId: r.subjectId,
    kind: _parse(EvidenceKind.values, r.kind),
    body: r.body,
    mediaId: r.mediaId,
    numberValue: r.numberValue,
    amountMga: r.amountMga,
    createdAt: _time(r.createdAt),
  );

  Future<List<Evidence>> evidencesOf(
    EvidenceSubject subject,
    String subjectId,
  ) async {
    final rows =
        await (_db.select(_db.evidences)
              ..where(
                (t) =>
                    t.subjectType.equals(_token(subject)) &
                    t.subjectId.equals(subjectId) &
                    t.deletedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    return rows.map(_evidence).toList();
  }

  Future<List<Conclusion>> conclusionsOf(String hypothesisId) async {
    final rows =
        await (_db.select(_db.conclusions)
              ..where(
                (t) =>
                    t.hypothesisId.equals(hypothesisId) & t.deletedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    return [
      for (final r in rows)
        Conclusion(
          id: r.id,
          hypothesisId: r.hypothesisId,
          experimentId: r.experimentId,
          statement: r.statement,
          outcome: _parse(HypothesisStatus.values, r.outcome),
          confidenceAfter: r.confidenceAfter,
          createdAt: _time(r.createdAt),
        ),
    ];
  }

  Future<List<Decision>> decisionsOf(String hypothesisId) async {
    final rows =
        await (_db.select(_db.decisions)
              ..where(
                (t) =>
                    t.hypothesisId.equals(hypothesisId) & t.deletedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.decidedAt)]))
            .get();
    return [
      for (final r in rows)
        Decision(
          id: r.id,
          hypothesisId: r.hypothesisId,
          experimentId: r.experimentId,
          kind: HypothesisTokens.decisionOf(r.decision),
          rationale: r.rationale,
          newHypothesisId: r.newHypothesisId,
          decidedAt: _time(r.decidedAt),
        ),
    ];
  }

  Future<List<Observation>> observationsOf(String projectId) async {
    final rows =
        await (_db.select(_db.observations)
              ..where(
                (t) => t.projectId.equals(projectId) & t.deletedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.observedAt)]))
            .get();
    return [
      for (final r in rows)
        Observation(
          id: r.id,
          projectId: r.projectId,
          description: r.description,
          context: r.context,
          supposedProblem: r.supposedProblem,
          observedAt: _time(r.observedAt),
        ),
    ];
  }

  Future<List<Interview>> interviewsOf(String projectId) async {
    final rows =
        await (_db.select(_db.interviews)
              ..where(
                (t) => t.projectId.equals(projectId) & t.deletedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.heldAt)]))
            .get();
    return [
      for (final r in rows)
        Interview(
          id: r.id,
          projectId: r.projectId,
          intervieweeAlias: r.intervieweeAlias,
          notes: r.notes,
          conclusion: r.conclusion,
          heldAt: _time(r.heldAt),
        ),
    ];
  }

  /// What the guards need to know about a hypothesis' tests.
  Future<TestFacts> testFacts(String hypothesisId) async {
    final experiments = await experimentsFor(hypothesisId);
    final running = experiments
        .where((e) => e.status == ExperimentStatus.running)
        .length;
    final experimentIds = experiments.map((e) => e.id).toList();
    final resultIds = <String>[];
    for (final id in experimentIds) {
      resultIds.addAll((await resultsOf(id)).map((r) => r.id));
    }
    var evidences = 0;
    for (final id in experimentIds) {
      evidences += (await evidencesOf(EvidenceSubject.experiment, id)).length;
    }
    for (final id in resultIds) {
      evidences += (await evidencesOf(EvidenceSubject.result, id)).length;
    }
    return TestFacts(
      runningExperiments: running,
      results: resultIds.length,
      evidences: evidences,
    );
  }

  /// Fires on any change of the research tables (screens re-read).
  Stream<void> watchChanges() => _db.tableUpdates(
    TableUpdateQuery.onAllTables([
      _db.hypotheses,
      _db.experiments,
      _db.experimentHypotheses,
      _db.results,
      _db.evidences,
      _db.conclusions,
      _db.decisions,
      _db.observations,
      _db.interviews,
    ]),
  );

  // ------------------------------------------------------- hypotheses

  Future<void> _setStatus(String hypothesisId, HypothesisStatus status) async {
    await (_db.update(
      _db.hypotheses,
    )..where((t) => t.id.equals(hypothesisId))).write(
      HypothesesCompanion(
        status: Value(_token(status)),
        updatedAt: Value(_now()),
      ),
    );
    await _sync.markChanged(EntityTypes.hypothesis, hypothesisId);
  }

  Future<void> _move(String hypothesisId, HypothesisStatus to) async {
    final h = await _requireHypothesis(hypothesisId);
    HypothesisRules.checkMove(h.status, to, await testFacts(hypothesisId));
    await _setStatus(hypothesisId, to);
  }

  Future<Hypothesis> _insertHypothesis({
    required String projectId,
    required String statement,
    required HypothesisCategory category,
    required int importance,
    int? confidenceBefore,
    String? parentHypothesisId,
    String? sourceStepId,
  }) async {
    final text = HypothesisRules.checkText(
      statement,
      HypothesisRules.maxStatementLength,
    );
    if (importance < 1 || importance > 3) _fail(GuardFailure.invalidText);
    if (confidenceBefore != null) {
      HypothesisRules.checkConfidence(confidenceBefore);
    }
    final id = Ids.newId();
    final now = _now();
    await _db
        .into(_db.hypotheses)
        .insert(
          HypothesesCompanion.insert(
            id: id,
            projectId: projectId,
            statement: text,
            category: _token(category),
            importance: Value(importance),
            confidenceBefore: Value(confidenceBefore),
            status: _token(HypothesisStatus.draft),
            parentHypothesisId: Value(parentHypothesisId),
            sourceStepId: Value(sourceStepId),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _sync.markChanged(EntityTypes.hypothesis, id);
    return (await hypothesis(id))!;
  }

  Future<Hypothesis> createHypothesis({
    required String projectId,
    required String statement,
    HypothesisCategory category = HypothesisCategory.other,
    int importance = 2,
    int? confidenceBefore,
    String? sourceStepId,
  }) => _db.transaction(
    () => _insertHypothesis(
      projectId: projectId,
      statement: statement,
      category: category,
      importance: importance,
      confidenceBefore: confidenceBefore,
      sourceStepId: sourceStepId,
    ),
  );

  /// Edits a hypothesis that has not been tested yet (rule 4).
  Future<void> editHypothesis(
    String id, {
    String? statement,
    HypothesisCategory? category,
    int? importance,
    int? confidenceBefore,
  }) => _db.transaction(() async {
    final h = await _requireHypothesis(id);
    if (!h.status.isEditable) _fail(GuardFailure.notEditable);
    if (confidenceBefore != null) {
      HypothesisRules.checkConfidence(confidenceBefore);
    }
    if (importance != null && (importance < 1 || importance > 3)) {
      _fail(GuardFailure.invalidText);
    }
    await (_db.update(_db.hypotheses)..where((t) => t.id.equals(id))).write(
      HypothesesCompanion(
        statement: statement == null
            ? const Value.absent()
            : Value(
                HypothesisRules.checkText(
                  statement,
                  HypothesisRules.maxStatementLength,
                ),
              ),
        category: category == null
            ? const Value.absent()
            : Value(_token(category)),
        importance: importance == null
            ? const Value.absent()
            : Value(importance),
        confidenceBefore: confidenceBefore == null
            ? const Value.absent()
            : Value(confidenceBefore),
        updatedAt: Value(_now()),
      ),
    );
    await _sync.markChanged(EntityTypes.hypothesis, id);
  });

  Future<void> markToTest(String id) =>
      _db.transaction(() => _move(id, HypothesisStatus.toTest));

  /// Abandons a hypothesis before or between tests (a test in progress is
  /// cancelled first; a tested one is kept as a result).
  Future<void> abandon(String id) =>
      _db.transaction(() => _move(id, HypothesisStatus.abandoned));

  // ------------------------------------------------------ experiments

  Future<Experiment> planExperiment({
    required String projectId,
    required ExperimentMethod method,
    required String plan,
    required List<String> hypothesisIds,
    String? successCriterion,
    int? sampleTarget,
    String? missionInstanceId,
  }) => _db.transaction(() async {
    if (hypothesisIds.isEmpty) _fail(GuardFailure.notFound);
    final text = HypothesisRules.checkText(plan, ExperimentRules.maxPlanLength);
    final criterion = _optionalText(
      successCriterion,
      ExperimentRules.maxCriterionLength,
    );
    if (sampleTarget != null && sampleTarget < 1) {
      _fail(GuardFailure.invalidMetrics);
    }
    final hypotheses = [
      for (final id in hypothesisIds) await _requireHypothesis(id),
    ];
    final id = Ids.newId();
    final now = _now();
    await _db
        .into(_db.experiments)
        .insert(
          ExperimentsCompanion.insert(
            id: id,
            projectId: projectId,
            method: _token(method),
            plan: text,
            successCriterion: Value(criterion),
            sampleTarget: Value(sampleTarget),
            status: _token(ExperimentStatus.planned),
            missionInstanceId: Value(missionInstanceId),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _sync.markChanged(EntityTypes.experiment, id);
    for (final h in hypotheses) {
      final linkId = Ids.forKey('experiment_hypothesis:$id/${h.id}');
      await _db
          .into(_db.experimentHypotheses)
          .insert(
            ExperimentHypothesesCompanion.insert(
              id: linkId,
              experimentId: id,
              hypothesisId: h.id,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _sync.markChanged(EntityTypes.experimentHypothesis, linkId);
      // Planning a test of a draft makes it "to test".
      if (h.status == HypothesisStatus.draft) {
        await _move(h.id, HypothesisStatus.toTest);
      }
    }
    return (await experiment(id))!;
  });

  /// Changes the plan; the criterion only while the test has not started.
  Future<void> editExperiment(
    String id, {
    String? plan,
    String? successCriterion,
    int? sampleTarget,
  }) => _db.transaction(() async {
    final e = await _requireExperiment(id);
    if (e.status.isFinished) _fail(GuardFailure.notEditable);
    if (successCriterion != null || sampleTarget != null) {
      ExperimentRules.checkCriterionEditable(e.status);
    }
    await (_db.update(_db.experiments)..where((t) => t.id.equals(id))).write(
      ExperimentsCompanion(
        plan: plan == null
            ? const Value.absent()
            : Value(
                HypothesisRules.checkText(plan, ExperimentRules.maxPlanLength),
              ),
        successCriterion: successCriterion == null
            ? const Value.absent()
            : Value(
                _optionalText(
                  successCriterion,
                  ExperimentRules.maxCriterionLength,
                ),
              ),
        sampleTarget: sampleTarget == null
            ? const Value.absent()
            : Value(sampleTarget),
        updatedAt: Value(_now()),
      ),
    );
    await _sync.markChanged(EntityTypes.experiment, id);
  });

  Future<void> _setExperiment(String id, ExperimentsCompanion changes) async {
    await (_db.update(_db.experiments)..where((t) => t.id.equals(id))).write(
      changes.copyWith(updatedAt: Value(_now())),
    );
    await _sync.markChanged(EntityTypes.experiment, id);
  }

  /// Starts the test: the criterion is locked, the hypotheses waiting for a
  /// test are now being tested.
  Future<void> startExperiment(String id) => _db.transaction(() async {
    final e = await _requireExperiment(id);
    ExperimentRules.checkMove(
      e.status,
      ExperimentStatus.running,
      hasCriterion: e.successCriterion != null,
      results: 0,
    );
    final now = _now();
    await _setExperiment(
      id,
      ExperimentsCompanion(
        status: Value(_token(ExperimentStatus.running)),
        criterionLockedAt: Value(now),
        startedAt: Value(now),
      ),
    );
    for (final hId in e.hypothesisIds) {
      final h = await _requireHypothesis(hId);
      if (h.status == HypothesisStatus.toTest ||
          h.status == HypothesisStatus.inconclusive) {
        await _move(hId, HypothesisStatus.testing);
      }
    }
  });

  Future<ExperimentResult> recordResult(
    String experimentId, {
    required String summary,
    int? yes,
    int? total,
  }) => _db.transaction(() async {
    final e = await _requireExperiment(experimentId);
    if (e.status != ExperimentStatus.running &&
        e.status != ExperimentStatus.done) {
      _fail(GuardFailure.experimentNotStarted);
    }
    ExperimentRules.checkMetrics(yes, total);
    final text = HypothesisRules.checkText(
      summary,
      FieldNoteRules.maxShortLength,
    );
    final id = Ids.newId();
    final now = _now();
    await _db
        .into(_db.results)
        .insert(
          ResultsCompanion.insert(
            id: id,
            experimentId: experimentId,
            summary: text,
            metricYes: Value(yes),
            metricTotal: Value(total),
            recordedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _sync.markChanged(EntityTypes.result, id);
    return (await resultsOf(experimentId)).firstWhere((r) => r.id == id);
  });

  Future<void> finishExperiment(String id) => _db.transaction(() async {
    final e = await _requireExperiment(id);
    ExperimentRules.checkMove(
      e.status,
      ExperimentStatus.done,
      hasCriterion: e.successCriterion != null,
      results: (await resultsOf(id)).length,
    );
    await _setExperiment(
      id,
      ExperimentsCompanion(
        status: Value(_token(ExperimentStatus.done)),
        endedAt: Value(_now()),
      ),
    );
  });

  /// Cancels a test. A hypothesis that was only tested by it goes back to
  /// "to test" (nothing was concluded).
  Future<void> cancelExperiment(String id) => _db.transaction(() async {
    final e = await _requireExperiment(id);
    ExperimentRules.checkMove(
      e.status,
      ExperimentStatus.cancelled,
      hasCriterion: e.successCriterion != null,
      results: 0,
    );
    await _setExperiment(
      id,
      ExperimentsCompanion(
        status: Value(_token(ExperimentStatus.cancelled)),
        endedAt: Value(_now()),
      ),
    );
    for (final hId in e.hypothesisIds) {
      final h = await _requireHypothesis(hId);
      if (h.status != HypothesisStatus.testing) continue;
      final others = (await experimentsFor(hId)).where(
        (x) =>
            x.id != id &&
            (x.status == ExperimentStatus.running ||
                x.status == ExperimentStatus.done),
      );
      if (others.isEmpty) await _move(hId, HypothesisStatus.toTest);
    }
  });

  // ---------------------------------------------------------- evidence

  Future<Evidence> addEvidence({
    required String projectId,
    required EvidenceSubject subject,
    required String subjectId,
    required EvidenceKind kind,
    String? body,
    String? mediaId,
    double? numberValue,
    int? amountMga,
  }) => _db.transaction(() async {
    final complete = switch (kind) {
      EvidenceKind.note ||
      EvidenceKind.link => body != null && body.trim().isNotEmpty,
      EvidenceKind.photo => mediaId != null,
      EvidenceKind.number => numberValue != null && numberValue.isFinite,
      EvidenceKind.sale => amountMga != null && amountMga >= 0,
    };
    if (!complete) _fail(GuardFailure.incompleteEvidence);
    final text = _optionalText(
      body,
      kind == EvidenceKind.link
          ? FieldNoteRules.maxLinkLength
          : FieldNoteRules.maxNotesLength,
    );
    final id = Ids.newId();
    final now = _now();
    await _db
        .into(_db.evidences)
        .insert(
          EvidencesCompanion.insert(
            id: id,
            projectId: projectId,
            subjectType: _token(subject),
            subjectId: subjectId,
            kind: _token(kind),
            body: Value(text),
            mediaId: Value(mediaId),
            numberValue: Value(numberValue),
            amountMga: Value(amountMga),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _sync.markChanged(EntityTypes.evidence, id);
    return (await evidencesOf(
      subject,
      subjectId,
    )).firstWhere((e) => e.id == id);
  });

  // ------------------------------------------- conclusions and decisions

  /// Concludes a hypothesis being tested: validated, invalidated or
  /// inconclusive, with what the user now thinks (rule 3).
  Future<Conclusion> conclude(
    String hypothesisId, {
    required HypothesisStatus outcome,
    required String statement,
    required int confidenceAfter,
    String? experimentId,
  }) => _db.transaction(() async {
    if (!outcome.isConcluded) _fail(GuardFailure.decisionNotAllowed);
    final text = HypothesisRules.checkText(
      statement,
      HypothesisRules.maxConclusionLength,
    );
    HypothesisRules.checkConfidence(confidenceAfter);
    await _move(hypothesisId, outcome);
    final id = Ids.newId();
    final now = _now();
    await _db
        .into(_db.conclusions)
        .insert(
          ConclusionsCompanion.insert(
            id: id,
            hypothesisId: hypothesisId,
            experimentId: Value(experimentId),
            statement: text,
            outcome: _token(outcome),
            confidenceAfter: confidenceAfter,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _sync.markChanged(EntityTypes.conclusion, id);
    return (await conclusionsOf(hypothesisId)).last;
  });

  /// Records a decision (append-only) and applies its effect:
  /// "test more" / "abandon" change the status, "modify" creates a new
  /// version with [newStatement], "go back" reopens the source step.
  Future<Decision> decide(
    String hypothesisId, {
    required DecisionKind kind,
    required String rationale,
    String? newStatement,
    String? experimentId,
  }) => _db.transaction(() async {
    final h = await _requireHypothesis(hypothesisId);
    final text = HypothesisRules.checkText(
      rationale,
      HypothesisRules.maxRationaleLength,
    );
    final next = HypothesisRules.statusAfter(
      kind,
      h.status,
      await testFacts(hypothesisId),
    );
    if (next != null) await _move(hypothesisId, next);

    String? newId;
    if (kind == DecisionKind.modify) {
      newId = (await _insertHypothesis(
        projectId: h.projectId,
        statement: newStatement ?? _fail(GuardFailure.invalidText),
        category: h.category,
        importance: h.importance,
        parentHypothesisId: h.id,
        sourceStepId: h.sourceStepId,
      )).id;
    }
    if (kind == DecisionKind.goBack) {
      final stepId = h.sourceStepId;
      final questId = stepId == null ? null : _questOfStep?.call(stepId);
      if (stepId != null && questId != null) {
        await _progress.setStatus(questId, stepId, StepStatus.inProgress);
      }
    }

    final id = Ids.newId();
    final now = _now();
    await _db
        .into(_db.decisions)
        .insert(
          DecisionsCompanion.insert(
            id: id,
            hypothesisId: hypothesisId,
            experimentId: Value(experimentId),
            decision: HypothesisTokens.decision(kind),
            rationale: text,
            newHypothesisId: Value(newId),
            decidedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _sync.markChanged(EntityTypes.decision, id);
    return (await decisionsOf(hypothesisId)).last;
  });

  // ------------------------------------------------------- field notes

  Future<Observation> addObservation({
    required String projectId,
    required String description,
    String? context,
    String? supposedProblem,
    DateTime? observedAt,
  }) => _db.transaction(() async {
    final id = Ids.newId();
    final now = _now();
    await _db
        .into(_db.observations)
        .insert(
          ObservationsCompanion.insert(
            id: id,
            projectId: projectId,
            description: HypothesisRules.checkText(
              description,
              FieldNoteRules.maxNotesLength,
            ),
            context: Value(
              _optionalText(context, FieldNoteRules.maxShortLength),
            ),
            supposedProblem: Value(
              _optionalText(supposedProblem, FieldNoteRules.maxShortLength),
            ),
            observedAt: observedAt?.millisecondsSinceEpoch ?? now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _sync.markChanged(EntityTypes.observation, id);
    return (await observationsOf(projectId)).firstWhere((o) => o.id == id);
  });

  /// A conversation: a pseudonym (never a full name or phone number) and
  /// written notes.
  Future<Interview> addInterview({
    required String projectId,
    required String alias,
    required String notes,
    String? conclusion,
    DateTime? heldAt,
  }) => _db.transaction(() async {
    final id = Ids.newId();
    final now = _now();
    await _db
        .into(_db.interviews)
        .insert(
          InterviewsCompanion.insert(
            id: id,
            projectId: projectId,
            intervieweeAlias: HypothesisRules.checkText(
              alias,
              FieldNoteRules.maxAliasLength,
            ),
            notes: HypothesisRules.checkText(
              notes,
              FieldNoteRules.maxNotesLength,
            ),
            conclusion: Value(
              _optionalText(conclusion, FieldNoteRules.maxShortLength),
            ),
            heldAt: heldAt?.millisecondsSinceEpoch ?? now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _sync.markChanged(EntityTypes.interview, id);
    return (await interviewsOf(projectId)).firstWhere((i) => i.id == id);
  });
}
