import 'content_pack.dart';
import 'progress_state.dart';
import 'rules.dart';

/// Stored progress of one step (from the local database).
class StepRecord {
  const StepRecord(this.status, {this.completedAt, this.deferredUntil});
  final StepStatus status;
  final DateTime? completedAt;
  final DateTime? deferredUntil;
}

/// Stored state of one mission instance.
class MissionRecord {
  const MissionRecord(this.status, {this.acceptedAt, this.completedAt});
  final MissionStatus status;
  final DateTime? acceptedAt;
  final DateTime? completedAt;
}

/// Everything the planner reads. Only typed state: no free text.
class PlannerInput {
  const PlannerInput({
    required this.pack,
    required this.now,
    this.facts = const {},
    this.steps = const {},
    this.missions = const {},
    this.unknownAnswersByQuest = const {},
  });

  final ContentPack pack;
  final DateTime now;
  final Map<String, Object?> facts;
  final Map<String, StepRecord> steps;
  final Map<String, MissionRecord> missions;
  final Map<String, int> unknownAnswersByQuest;
}

/// Why a step cannot be started yet (shown as "what to do before").
enum LockReason { questLocked, previousStep, condition }

class PlannedStep {
  const PlannedStep({
    required this.step,
    required this.status,
    this.fastTrack = false,
    this.lockReason,
    this.resurfaced = false,
    this.deferredUntil,
  });

  final Step step;

  /// Status to show. [StepStatus.fastTracked] without a stored record means
  /// a learning step skipped for an advanced profile (still readable).
  final StepStatus status;

  /// Only the deliverable is asked (docs/PRODUCT_ARCHITECTURE.md §3.3).
  final bool fastTrack;
  final LockReason? lockReason;

  /// A deferred step whose waiting time is over.
  final bool resurfaced;
  final DateTime? deferredUntil;

  bool get isDone => status.isDone;
  bool get canStart =>
      status == StepStatus.available ||
      status == StepStatus.inProgress ||
      status == StepStatus.postponed ||
      status == StepStatus.deferred;
}

class PlannedQuest {
  const PlannedQuest({
    required this.quest,
    required this.available,
    required this.steps,
  });

  final Quest quest;
  final bool available;
  final List<PlannedStep> steps;

  int get done => steps.where((s) => s.isDone).length;
  int get total => steps.length;

  QuestState get state => done == total
      ? QuestState.completed
      : steps.any(
          (s) => s.isDone || s.status.rank == StepStatus.inProgress.rank,
        )
      ? QuestState.inProgress
      : QuestState.notStarted;
}

class JourneyPlan {
  const JourneyPlan({
    required this.quests,
    required this.diagnostic,
    required this.next,
  });

  /// Journey quests in display order.
  final List<PlannedQuest> quests;

  /// Null when the pack has no diagnostic.
  final PlannedQuest? diagnostic;

  /// The one recommended next action (shown on the home screen).
  final PlannedStep? next;

  bool get diagnosticDone =>
      diagnostic == null || diagnostic!.state == QuestState.completed;

  PlannedStep? step(String stepId) {
    for (final q in [?diagnostic, ...quests]) {
      for (final s in q.steps) {
        if (s.step.id == stepId) return s;
      }
    }
    return null;
  }
}

/// Rule context over the stored state. Steps report their stored status
/// (rules test done-ness or progress, never "locked/available", which are
/// planner results).
class _Context implements RuleContext {
  _Context(this.input);
  final PlannerInput input;

  @override
  DateTime get now => input.now;

  @override
  Object? fact(String key) => input.facts[key];

  @override
  bool hasFact(String key) =>
      input.facts.containsKey(key) && input.facts[key] != null;

  @override
  StepStatus stepStatus(String stepId) =>
      input.steps[stepId]?.status ?? StepStatus.available;

  @override
  QuestState questState(String questId) {
    final quest = input.pack.quest(questId);
    if (quest == null) return QuestState.notStarted;
    final statuses = [for (final s in quest.steps) stepStatus(s.id)];
    if (statuses.every((s) => s.isDone)) return QuestState.completed;
    return quest.steps.any((s) => input.steps.containsKey(s.id))
        ? QuestState.inProgress
        : QuestState.notStarted;
  }

  @override
  MissionStatus? missionStatus(String missionId) =>
      input.missions[missionId]?.status;

  @override
  int count(String entity, Map<String, String> where) {
    switch (entity) {
      case 'missions':
        return input.missions.values
            .where(
              (m) =>
                  where['status'] == null ||
                  _token(m.status) == where['status'],
            )
            .length;
      case 'steps':
        return input.pack.steps.where((s) {
          if (where['quest'] != null &&
              input.pack.questOfStep(s.id)!.id != where['quest']) {
            return false;
          }
          return where['status'] == null ||
              _token(stepStatus(s.id)) == where['status'];
        }).length;
      case 'quests':
        return input.pack.quests
            .where(
              (q) =>
                  where['state'] == null ||
                  _token(questState(q.id)) == where['state'],
            )
            .length;
      case 'unknown_answers':
        final quest = where['quest'];
        return quest == null
            ? input.unknownAnswersByQuest.values.fold(0, (a, b) => a + b)
            : input.unknownAnswersByQuest[quest] ?? 0;
    }
    return 0;
  }

  @override
  DateTime? eventTime(EventSubject subject) => switch (subject.kind) {
    EventKind.stepCompleted => input.steps[subject.id]?.completedAt,
    EventKind.missionAccepted => input.missions[subject.id]?.acceptedAt,
    EventKind.missionCompleted => input.missions[subject.id]?.completedAt,
  };

  static String _token(Enum e) => e.name.replaceAllMapped(
    RegExp('[A-Z]'),
    (m) => '_${m[0]!.toLowerCase()}',
  );
}

/// Pure and deterministic: the same input always gives the same plan
/// (docs/PRODUCT_ARCHITECTURE.md §3.3).
JourneyPlan plan(PlannerInput input) {
  final context = _Context(input);

  PlannedQuest planQuest(Quest quest) {
    final available = quest.availableWhen?.evaluate(context) ?? true;
    final planned = <PlannedStep>[];
    for (var i = 0; i < quest.steps.length; i++) {
      final step = quest.steps[i];
      final record = input.steps[step.id];
      final fastTrack =
          (step.fastTrackWhen ?? quest.fastTrackWhen)?.evaluate(context) ??
          false;

      if (record != null && record.status.isDone) {
        planned.add(PlannedStep(step: step, status: record.status));
        continue;
      }
      if (!available) {
        planned.add(
          PlannedStep(
            step: step,
            status: StepStatus.locked,
            lockReason: LockReason.questLocked,
          ),
        );
        continue;
      }
      // A step skipped for now or postponed does not block the next ones.
      final previousPassed =
          i == 0 ||
          planned[i - 1].isDone ||
          planned[i - 1].status == StepStatus.deferred ||
          planned[i - 1].status == StepStatus.postponed ||
          planned[i - 1].resurfaced;
      final unlocked = step.availableWhen?.evaluate(context) ?? previousPassed;
      if (!unlocked) {
        planned.add(
          PlannedStep(
            step: step,
            status: StepStatus.locked,
            lockReason: step.availableWhen == null
                ? LockReason.previousStep
                : LockReason.condition,
          ),
        );
        continue;
      }
      // Advanced profile, nothing to deliver: skipped but readable.
      if (fastTrack &&
          step.outputs.isEmpty &&
          step.missionIds.isEmpty &&
          step.completeWhen == null &&
          record == null) {
        planned.add(
          PlannedStep(
            step: step,
            status: StepStatus.fastTracked,
            fastTrack: true,
          ),
        );
        continue;
      }
      switch (record?.status) {
        case StepStatus.deferred:
          final until = record!.deferredUntil;
          final over = until == null || !input.now.isBefore(until);
          planned.add(
            PlannedStep(
              step: step,
              status: over ? StepStatus.available : StepStatus.deferred,
              fastTrack: fastTrack,
              resurfaced: over,
              deferredUntil: until,
            ),
          );
        case StepStatus.postponed:
          planned.add(
            PlannedStep(
              step: step,
              status: StepStatus.postponed,
              fastTrack: fastTrack,
            ),
          );
        case StepStatus.inProgress:
          planned.add(
            PlannedStep(
              step: step,
              status: StepStatus.inProgress,
              fastTrack: fastTrack,
            ),
          );
        default:
          planned.add(
            PlannedStep(
              step: step,
              status: StepStatus.available,
              fastTrack: fastTrack,
            ),
          );
      }
    }
    return PlannedQuest(quest: quest, available: available, steps: planned);
  }

  final diagnosticQuest = input.pack.diagnostic;
  final diagnostic = diagnosticQuest == null
      ? null
      : planQuest(diagnosticQuest);
  final quests = [for (final q in input.pack.journey) planQuest(q)];

  PlannedStep? next;
  if (diagnostic != null && diagnostic.state != QuestState.completed) {
    next = _firstActionable(diagnostic);
  } else {
    final candidates = quests.where((q) => q.available).toList()
      ..sort((a, b) {
        final byPriority = b.quest.priority.compareTo(a.quest.priority);
        return byPriority != 0
            ? byPriority
            : a.quest.order.compareTo(b.quest.order);
      });
    // Steps in progress first, then new ones, then those set aside.
    for (final pass in _passes) {
      for (final q in candidates) {
        for (final s in q.steps) {
          if (pass(s)) {
            next = s;
            break;
          }
        }
        if (next != null) break;
      }
      if (next != null) break;
    }
  }
  return JourneyPlan(quests: quests, diagnostic: diagnostic, next: next);
}

final _passes = <bool Function(PlannedStep)>[
  (s) => s.status == StepStatus.inProgress,
  (s) => s.status == StepStatus.available,
  (s) => s.status == StepStatus.postponed,
];

PlannedStep? _firstActionable(PlannedQuest quest) {
  for (final s in quest.steps) {
    if (s.canStart && s.status != StepStatus.deferred) return s;
  }
  return null;
}
