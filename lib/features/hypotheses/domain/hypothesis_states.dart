// Hypothesis → experiment → result → evidence → conclusion → decision
// (docs/PRODUCT_ARCHITECTURE.md §4). Pure Dart: the state machines and the
// rules that guard them, tested exhaustively.

/// Life cycle of a hypothesis (§4.1).
///
/// ```
/// draft ──► to_test ──► testing ──► validated | invalidated | inconclusive
///   └──────────┴──────────────► abandoned        inconclusive ──► testing
/// testing ──► to_test (its last running experiment was cancelled)
/// inconclusive ──► to_test | abandoned (decision "test more" / "abandon")
/// ```
///
/// Validated, invalidated and abandoned are final: changing a tested
/// hypothesis creates a new version linked to it (rule 4).
enum HypothesisStatus {
  draft,
  toTest,
  testing,
  validated,
  invalidated,
  inconclusive,
  abandoned;

  /// A conclusion has been reached (decisions can be taken).
  bool get isConcluded =>
      this == validated || this == invalidated || this == inconclusive;

  /// The statement can still be edited in place (never after a test).
  bool get isEditable => this == draft || this == toTest;
}

enum HypothesisCategory { problem, customer, solution, price, channel, other }

/// Life cycle of an experiment (§4.2): `planned → running → done |
/// cancelled`, plus `planned → cancelled`. The success criterion can only
/// be changed while planned, and is locked when the experiment starts.
enum ExperimentStatus {
  planned,
  running,
  done,
  cancelled;

  bool get isFinished => this == done || this == cancelled;
}

enum ExperimentMethod {
  interview,
  observation,
  prototype,
  priceTest,
  preSale,
  freeTrial,
  other,
}

/// Decisions taken after a conclusion (append-only journal, §4.3).
enum DecisionKind {
  /// Keep going with what was learned (stored as `continue`).
  keepGoing,

  /// Write a new version of the hypothesis (linked to this one).
  modify,

  /// Plan another test (inconclusive only).
  testMore,

  /// Stop working on this hypothesis (inconclusive only: a validated or
  /// invalidated hypothesis is a result, kept as it is).
  abandon,

  /// Go back to the journey step the hypothesis came from.
  goBack,
}

/// What a piece of evidence is (§4.3). Audio and documents come later
/// (DEVELOPMENT_PLAN, Phase 4: recordings of other people wait for the
/// legal advice P6).
enum EvidenceKind { note, photo, link, number, sale }

/// What a piece of evidence is attached to.
enum EvidenceSubject {
  experiment,
  result,
  observation,
  interview,
  missionInstance,
  projectSection,
}

/// A move the machine does not allow from the current status.
class InvalidHypothesisTransition implements Exception {
  const InvalidHypothesisTransition(this.from, this.to);
  final HypothesisStatus from;
  final HypothesisStatus to;
}

class InvalidExperimentTransition implements Exception {
  const InvalidExperimentTransition(this.from, this.to);
  final ExperimentStatus from;
  final ExperimentStatus to;
}

/// Why a move allowed by the machine is refused by a business rule.
enum GuardFailure {
  /// Testing needs a running experiment (criterion defined before the
  /// test, rule 2).
  noRunningExperiment,

  /// An experiment cannot start without a success criterion.
  noSuccessCriterion,

  /// The criterion is locked once the experiment has started.
  criterionLocked,

  /// A conclusion needs at least one result (rule 3).
  noResult,

  /// Validated / invalidated need at least one piece of evidence (rule 3).
  noEvidence,

  /// An experiment is done only with at least one result.
  experimentWithoutResult,

  /// The statement cannot change after a test (rule 4): create a version.
  notEditable,

  /// This decision does not apply to the hypothesis' status.
  decisionNotAllowed,

  /// Confidence is a whole number from 1 to 5.
  invalidConfidence,

  /// Required text is empty or too long.
  invalidText,

  /// A result's numbers are inconsistent (0 ≤ yes ≤ total, total ≥ 1).
  invalidMetrics,

  /// Results are recorded on a running or finished experiment only.
  experimentNotStarted,

  /// The evidence lacks what its kind needs (text, photo, number, amount).
  incompleteEvidence,

  /// Unknown hypothesis, experiment or subject.
  notFound,
}

class GuardViolation implements Exception {
  const GuardViolation(this.failure);
  final GuardFailure failure;
}

abstract final class HypothesisMachine {
  static const _allowed = <HypothesisStatus, Set<HypothesisStatus>>{
    HypothesisStatus.draft: {
      HypothesisStatus.toTest,
      HypothesisStatus.abandoned,
    },
    HypothesisStatus.toTest: {
      HypothesisStatus.testing,
      HypothesisStatus.abandoned,
    },
    HypothesisStatus.testing: {
      HypothesisStatus.validated,
      HypothesisStatus.invalidated,
      HypothesisStatus.inconclusive,
      HypothesisStatus.toTest,
    },
    HypothesisStatus.inconclusive: {
      HypothesisStatus.testing,
      HypothesisStatus.toTest,
      HypothesisStatus.abandoned,
    },
    HypothesisStatus.validated: {},
    HypothesisStatus.invalidated: {},
    HypothesisStatus.abandoned: {},
  };

  static bool canMove(HypothesisStatus from, HypothesisStatus to) =>
      _allowed[from]!.contains(to);

  static void check(HypothesisStatus from, HypothesisStatus to) {
    if (!canMove(from, to)) throw InvalidHypothesisTransition(from, to);
  }

  /// Statuses reachable in one move.
  static Set<HypothesisStatus> next(HypothesisStatus from) =>
      Set.unmodifiable(_allowed[from]!);
}

abstract final class ExperimentMachine {
  static const _allowed = <ExperimentStatus, Set<ExperimentStatus>>{
    ExperimentStatus.planned: {
      ExperimentStatus.running,
      ExperimentStatus.cancelled,
    },
    ExperimentStatus.running: {
      ExperimentStatus.done,
      ExperimentStatus.cancelled,
    },
    ExperimentStatus.done: {},
    ExperimentStatus.cancelled: {},
  };

  static bool canMove(ExperimentStatus from, ExperimentStatus to) =>
      _allowed[from]!.contains(to);

  static void check(ExperimentStatus from, ExperimentStatus to) {
    if (!canMove(from, to)) throw InvalidExperimentTransition(from, to);
  }
}

/// Facts about a hypothesis' tests that the guards read.
class TestFacts {
  const TestFacts({
    this.runningExperiments = 0,
    this.results = 0,
    this.evidences = 0,
  });

  /// Running experiments linked to the hypothesis.
  final int runningExperiments;

  /// Results recorded on experiments linked to the hypothesis.
  final int results;

  /// Evidence attached to those experiments or their results.
  final int evidences;
}

/// Business rules on top of the machines (§4.1 rules 2–4). Pure: the
/// service gathers the facts and applies the result in one transaction.
abstract final class HypothesisRules {
  static const maxStatementLength = 500;
  static const maxConclusionLength = 1000;
  static const maxRationaleLength = 1000;

  /// The hypothesis may move from [from] to [to] given [facts].
  static void checkMove(
    HypothesisStatus from,
    HypothesisStatus to,
    TestFacts facts,
  ) {
    HypothesisMachine.check(from, to);
    switch (to) {
      case HypothesisStatus.testing when facts.runningExperiments == 0:
        throw const GuardViolation(GuardFailure.noRunningExperiment);
      case HypothesisStatus.validated || HypothesisStatus.invalidated:
        if (facts.results == 0) {
          throw const GuardViolation(GuardFailure.noResult);
        }
        if (facts.evidences == 0) {
          throw const GuardViolation(GuardFailure.noEvidence);
        }
      case HypothesisStatus.inconclusive when facts.results == 0:
        throw const GuardViolation(GuardFailure.noResult);
      default:
    }
  }

  /// Decisions that can be taken on a hypothesis in [status].
  static Set<DecisionKind> decisionsFor(HypothesisStatus status) =>
      switch (status) {
        HypothesisStatus.inconclusive => DecisionKind.values.toSet(),
        HypothesisStatus.validated || HypothesisStatus.invalidated => {
          DecisionKind.keepGoing,
          DecisionKind.modify,
          DecisionKind.goBack,
        },
        _ => const {},
      };

  /// Status after [decision] on a hypothesis in [status]; null = unchanged.
  /// "Test more" goes back to testing only if an experiment is already
  /// running, otherwise to "to test" (a new experiment must be planned,
  /// with its criterion set before the test).
  static HypothesisStatus? statusAfter(
    DecisionKind decision,
    HypothesisStatus status,
    TestFacts facts,
  ) {
    if (!decisionsFor(status).contains(decision)) {
      throw const GuardViolation(GuardFailure.decisionNotAllowed);
    }
    return switch (decision) {
      DecisionKind.testMore =>
        facts.runningExperiments > 0
            ? HypothesisStatus.testing
            : HypothesisStatus.toTest,
      DecisionKind.abandon => HypothesisStatus.abandoned,
      _ => null,
    };
  }

  static void checkConfidence(int value) {
    if (value < 1 || value > 5) {
      throw const GuardViolation(GuardFailure.invalidConfidence);
    }
  }

  /// Trimmed text, or [GuardFailure.invalidText] if empty or too long.
  static String checkText(String text, int maxLength) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > maxLength) {
      throw const GuardViolation(GuardFailure.invalidText);
    }
    return trimmed;
  }
}

abstract final class ExperimentRules {
  static const maxPlanLength = 1000;
  static const maxCriterionLength = 300;

  /// The experiment may move from [from] to [to].
  static void checkMove(
    ExperimentStatus from,
    ExperimentStatus to, {
    required bool hasCriterion,
    required int results,
  }) {
    ExperimentMachine.check(from, to);
    if (to == ExperimentStatus.running && !hasCriterion) {
      throw const GuardViolation(GuardFailure.noSuccessCriterion);
    }
    if (to == ExperimentStatus.done && results == 0) {
      throw const GuardViolation(GuardFailure.experimentWithoutResult);
    }
  }

  /// The success criterion can be changed only before the test starts.
  static void checkCriterionEditable(ExperimentStatus status) {
    if (status != ExperimentStatus.planned) {
      throw const GuardViolation(GuardFailure.criterionLocked);
    }
  }

  /// `yes` out of `total`, both whole numbers, 0 ≤ yes ≤ total, total ≥ 1.
  static void checkMetrics(int? yes, int? total) {
    if (yes == null && total == null) return;
    if (yes == null || total == null || total < 1 || yes < 0 || yes > total) {
      throw const GuardViolation(GuardFailure.invalidMetrics);
    }
  }
}

/// Stored tokens (snake_case), never renamed: they are in synced payloads.
abstract final class HypothesisTokens {
  static String decision(DecisionKind d) =>
      d == DecisionKind.keepGoing ? 'continue' : _snake(d.name);

  static DecisionKind decisionOf(String token) =>
      DecisionKind.values.firstWhere((d) => decision(d) == token);

  static String of(Enum e) => _snake(e.name);

  static T parse<T extends Enum>(List<T> values, String token) =>
      values.firstWhere((v) => _snake(v.name) == token);

  static String _snake(String camel) =>
      camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
}
