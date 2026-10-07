import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;

import '../../../content/content_pack.dart';
import '../../../content/planner.dart';
import '../../../content/progress_state.dart';
import '../../../content/rules.dart' show unknownFactValue;
import '../../../core/time/clock.dart';
import '../../../data/local/app_database.dart';
import '../../diagnostic/data/facts_repository.dart';
import '../../missions/data/mission_repository.dart';
import '../../missions/domain/mission_state.dart';
import '../../project/data/project_repository.dart';
import '../data/answer_repository.dart';
import '../data/progress_repository.dart';
import '../domain/answer.dart';

sealed class CompletionResult {
  const CompletionResult();
}

final class StepCompleted extends CompletionResult {
  const StepCompleted();
}

/// Required questions are not all answered.
final class MissingAnswers extends CompletionResult {
  const MissingAnswers(this.blockIds);
  final List<String> blockIds;
}

/// The step's own condition is not met yet (e.g. its mission is not done).
final class ConditionNotMet extends CompletionResult {
  const ConditionNotMet();
}

/// The quest journey: plan, step progress, answers, outputs and missions,
/// over the local database. All writes go through repositories (and are
/// thus marked for synchronisation).
class JourneyService {
  JourneyService({
    required this.pack,
    required this._db,
    Clock clock = systemClock,
  }) : _clock = clock,
       _progress = ProgressRepository(_db, clock: clock),
       _answers = AnswerRepository(_db, clock: clock),
       _facts = FactsRepository(_db, clock: clock),
       _projects = ProjectRepository(_db, clock: clock),
       _missions = MissionRepository(_db, clock: clock);

  final ContentPack pack;
  final AppDatabase _db;
  final Clock _clock;
  final ProgressRepository _progress;
  final AnswerRepository _answers;
  final FactsRepository _facts;
  final ProjectRepository _projects;
  final MissionRepository _missions;

  /// What the rules read: progress, facts and counted records.
  Future<PlannerInput> input() async {
    final steps = await _progress.all();
    final missions = await _missions.all();
    return PlannerInput(
      pack: pack,
      now: _clock(),
      facts: await _facts.all(),
      steps: {
        for (final e in steps.entries)
          e.key: StepRecord(
            e.value.status,
            completedAt: e.value.completedAt,
            deferredUntil: e.value.deferredUntil,
          ),
      },
      missions: {
        for (final m in missions)
          m.templateId: MissionRecord(
            m.status,
            acceptedAt: m.acceptedAt,
            completedAt: m.completedAt,
          ),
      },
      unknownAnswersByQuest: await _answers.unknownCountByQuest(),
      records: await _researchRecords(),
    );
  }

  /// Hypotheses, tests, evidence and field notes, as token fields only.
  Future<Map<String, List<Map<String, String>>>> _researchRecords() async {
    List<Map<String, String>> rows<T>(
      List<T> list,
      Map<String, String> Function(T) f,
    ) => [for (final r in list) f(r)];
    return {
      'hypotheses': rows(
        await (_db.select(
          _db.hypotheses,
        )..where((t) => t.deletedAt.isNull())).get(),
        (r) => {'status': r.status, 'category': r.category},
      ),
      'experiments': rows(
        await (_db.select(
          _db.experiments,
        )..where((t) => t.deletedAt.isNull())).get(),
        (r) => {'status': r.status, 'method': r.method},
      ),
      'evidences': rows(
        await (_db.select(
          _db.evidences,
        )..where((t) => t.deletedAt.isNull())).get(),
        (r) => {'kind': r.kind},
      ),
      'observations': rows(
        await (_db.select(
          _db.observations,
        )..where((t) => t.deletedAt.isNull())).get(),
        (_) => const {},
      ),
      'interviews': rows(
        await (_db.select(
          _db.interviews,
        )..where((t) => t.deletedAt.isNull())).get(),
        (_) => const {},
      ),
      'competitors': rows(
        await (_db.select(
          _db.competitors,
        )..where((t) => t.deletedAt.isNull())).get(),
        (r) => {'kind': r.kind},
      ),
      'finance_items': rows(
        await (_db.select(
          _db.financeItems,
        )..where((t) => t.deletedAt.isNull())).get(),
        (r) => {'kind': r.kind},
      ),
    };
  }

  Future<JourneyPlan> currentPlan() async => plan(await input());

  /// The plan, recomputed whenever the journey data changes. The table
  /// updates are listened to before the first plan is computed, so a change
  /// made meanwhile is never missed.
  Stream<JourneyPlan> watchPlan() {
    StreamSubscription<void>? updates;
    late final StreamController<void> triggers;
    triggers = StreamController<void>(
      onListen: () {
        updates = _db
            .tableUpdates(
              TableUpdateQuery.onAllTables([
                _db.stepProgressEntries,
                _db.answers,
                _db.facts,
                _db.missionInstances,
                _db.projects,
                _db.hypotheses,
                _db.experiments,
                _db.evidences,
                _db.observations,
                _db.interviews,
                _db.competitors,
                _db.financeItems,
              ]),
            )
            .listen((_) => triggers.add(null));
        triggers.add(null);
      },
      onCancel: () async {
        await updates?.cancel();
        await triggers.close();
      },
    );
    return triggers.stream.asyncMap((_) => currentPlan());
  }

  Future<Map<String, Answer>> answersOf(String stepId) =>
      _answers.forStep(stepId);

  Quest _questOf(String stepId) =>
      pack.questOfStep(stepId) ?? (throw ArgumentError.value(stepId));

  /// Opening a step marks it in progress (unless already done).
  Future<void> open(String stepId) async {
    final current = (await _progress.get(stepId))?.status;
    if (current != null &&
        (current.isDone || current == StepStatus.inProgress)) {
      return;
    }
    await _progress.setStatus(
      _questOf(stepId).id,
      stepId,
      StepStatus.inProgress,
    );
  }

  Future<void> saveAnswer(String stepId, String blockId, Answer answer) =>
      _answers.save(
        questId: _questOf(stepId).id,
        stepId: stepId,
        blockId: blockId,
        answer: answer,
      );

  /// "Skip for now": the step comes back after its delay.
  Future<void> skipForNow(String stepId) async {
    final step = pack.step(stepId)!;
    await _progress.setStatus(
      _questOf(stepId).id,
      stepId,
      StepStatus.deferred,
      deferredUntil: _clock().add(Duration(days: step.deferDays)),
    );
  }

  /// "Come back later": kept aside until the user returns to it.
  Future<void> comeBackLater(String stepId) =>
      _progress.setStatus(_questOf(stepId).id, stepId, StepStatus.postponed);

  /// Finishes a step: checks its answers and condition, applies its
  /// outputs (facts, project sections, project title) and records the
  /// completion — all in one transaction.
  ///
  /// [provisionalProjectTitle] names the project when the user answers
  /// "I don't know" to the title question and no project exists yet
  /// (the project exists from the end of the diagnostic, §7).
  Future<CompletionResult> complete(
    String stepId, {
    bool fastTrack = false,
    String? provisionalProjectTitle,
  }) async {
    final step = pack.step(stepId)!;
    final quest = _questOf(stepId);
    final answers = await _answers.forStep(stepId);
    final required = fastTrack
        ? (step.fastTrackBlocks.isNotEmpty
              ? step.fastTrackBlocks.toSet()
              : step.outputs.map((o) => o.fromBlock).toSet())
        : step.questions.where((q) => !q.optional).map((q) => q.id).toSet();
    final missing = [
      for (final q in step.questions)
        if (required.contains(q.id) && !answers.containsKey(q.id)) q.id,
    ];
    if (missing.isNotEmpty) return MissingAnswers(missing);
    if (step.completeWhen != null) {
      final ok = evaluateRule(step.completeWhen!, await input());
      if (!ok) return const ConditionNotMet();
    }

    final hasProject = await activeProjectId() != null;
    await _db.transaction(() async {
      final sections = <String, Map<String, Object?>>{};
      final trackedBySection = <String, Set<String>>{};
      String? projectTitle;
      for (final output in step.outputs) {
        final answer = answers[output.fromBlock];
        if (answer == null) continue; // optional question left empty
        switch (output.target) {
          case FactTarget(:final key):
            await _facts.set(
              key,
              answer.isUnknown ? unknownFactValue : answer.value,
              quest.kind == QuestKind.diagnostic
                  ? FactSource.diagnostic
                  : FactSource.user,
            );
          case SectionTarget(:final section, :final field, :final tracked):
            if (answer.isUnknown) continue;
            (sections[section] ??= {})[field] = answer.value;
            if (tracked) (trackedBySection[section] ??= {}).add(field);
          case ProjectTitleTarget():
            if (!answer.isUnknown) {
              projectTitle = answer.value! as String;
            } else if (!hasProject) {
              projectTitle = provisionalProjectTitle;
            }
        }
      }
      if (projectTitle != null) await _nameProject(projectTitle);
      if (sections.isNotEmpty) {
        final projectId = await _projectId();
        for (final entry in sections.entries) {
          final existing = await _projects.section(projectId, entry.key);
          await _projects.saveSection(
            projectId: projectId,
            sectionKey: entry.key,
            fields: {...?existing?.fields, ...entry.value},
            trackedFields: trackedBySection[entry.key] ?? const {},
          );
        }
      }
      await _progress.setStatus(
        quest.id,
        stepId,
        fastTrack ? StepStatus.fastTracked : StepStatus.completed,
      );
    });
    return const StepCompleted();
  }

  /// The project the journey builds (the first active one). The diagnostic
  /// creates it; until then there is none.
  Future<String?> activeProjectId() async {
    final projects = await _projects.active();
    return projects.isEmpty ? null : projects.first.id;
  }

  Future<String> _projectId() async =>
      await activeProjectId() ??
      (throw StateError('no project: the diagnostic comes first'));

  Future<void> _nameProject(String title) async {
    final id = await activeProjectId();
    if (id == null) {
      await _projects.create(title);
    } else {
      await _projects.rename(id, title);
    }
  }

  // ---------------------------------------------------------------- missions

  Future<void> acceptMission(String missionId) =>
      _missions.move(missionId, MissionStatus.accepted);

  Future<void> abandonMission(String missionId) =>
      _missions.move(missionId, MissionStatus.abandoned);

  /// Hands in the mission with the user's reflection; it is completed at
  /// once when the content's rule (if any) holds, otherwise it stays
  /// submitted until it does.
  Future<MissionStatus> submitMission(
    String missionId,
    String reflection,
  ) async {
    final text = reflection.trim();
    if (text.isEmpty) throw ArgumentError.value('(hidden)', 'reflection');
    final template = pack.mission(missionId)!;
    await _db.transaction(() async {
      final current = (await _missions.get(missionId))?.status;
      if (current == MissionStatus.accepted ||
          current == MissionStatus.inProgress) {
        await _missions.move(
          missionId,
          MissionStatus.submitted,
          reflection: text,
        );
      } else if (current == MissionStatus.submitted) {
        await _missions.move(missionId, MissionStatus.inProgress);
        await _missions.move(
          missionId,
          MissionStatus.submitted,
          reflection: text,
        );
      } else {
        throw StateError('mission not accepted');
      }
      final rule = template.completeWhen;
      if (rule == null || evaluateRule(rule, await input())) {
        await _missions.move(missionId, MissionStatus.completed);
      }
    });
    return (await _missions.get(missionId))!.status;
  }

  Stream<List<MissionInstance>> watchMissions() => _missions.watchAll();
}
