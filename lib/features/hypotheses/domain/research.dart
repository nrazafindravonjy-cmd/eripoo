import 'hypothesis_states.dart';

export 'hypothesis_states.dart';

/// "I think [who] has [problem] when [situation]" — written by the user,
/// never generated (§4.1 rule 1).
class Hypothesis {
  const Hypothesis({
    required this.id,
    required this.projectId,
    required this.statement,
    required this.category,
    required this.importance,
    required this.status,
    required this.createdAt,
    this.confidenceBefore,
    this.parentHypothesisId,
    this.sourceStepId,
  });

  final String id;
  final String projectId;
  final String statement;
  final HypothesisCategory category;

  /// 1 to 3.
  final int importance;
  final int? confidenceBefore;
  final HypothesisStatus status;
  final String? parentHypothesisId;
  final String? sourceStepId;
  final DateTime createdAt;
}

class Experiment {
  const Experiment({
    required this.id,
    required this.projectId,
    required this.method,
    required this.plan,
    required this.status,
    required this.hypothesisIds,
    this.successCriterion,
    this.criterionLockedAt,
    this.sampleTarget,
    this.startedAt,
    this.endedAt,
  });

  final String id;
  final String projectId;
  final ExperimentMethod method;
  final String plan;
  final String? successCriterion;
  final DateTime? criterionLockedAt;
  final int? sampleTarget;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final ExperimentStatus status;
  final List<String> hypothesisIds;
}

class ExperimentResult {
  const ExperimentResult({
    required this.id,
    required this.experimentId,
    required this.summary,
    required this.recordedAt,
    this.yes,
    this.total,
  });

  final String id;
  final String experimentId;
  final String summary;
  final int? yes;
  final int? total;
  final DateTime recordedAt;
}

class Evidence {
  const Evidence({
    required this.id,
    required this.projectId,
    required this.subject,
    required this.subjectId,
    required this.kind,
    required this.createdAt,
    this.body,
    this.mediaId,
    this.numberValue,
    this.amountMga,
  });

  final String id;
  final String projectId;
  final EvidenceSubject subject;
  final String subjectId;
  final EvidenceKind kind;

  /// Note text, link, or caption.
  final String? body;
  final String? mediaId;
  final double? numberValue;
  final int? amountMga;
  final DateTime createdAt;
}

class Conclusion {
  const Conclusion({
    required this.id,
    required this.hypothesisId,
    required this.statement,
    required this.outcome,
    required this.confidenceAfter,
    required this.createdAt,
    this.experimentId,
  });

  final String id;
  final String hypothesisId;
  final String? experimentId;
  final String statement;
  final HypothesisStatus outcome;
  final int confidenceAfter;
  final DateTime createdAt;
}

class Decision {
  const Decision({
    required this.id,
    required this.hypothesisId,
    required this.kind,
    required this.rationale,
    required this.decidedAt,
    this.experimentId,
    this.newHypothesisId,
  });

  final String id;
  final String hypothesisId;
  final String? experimentId;
  final DecisionKind kind;
  final String rationale;
  final String? newHypothesisId;
  final DateTime decidedAt;
}

class Observation {
  const Observation({
    required this.id,
    required this.projectId,
    required this.description,
    required this.observedAt,
    this.context,
    this.supposedProblem,
  });

  final String id;
  final String projectId;
  final String description;
  final String? context;
  final String? supposedProblem;
  final DateTime observedAt;
}

/// Pseudonym and written notes only.
class Interview {
  const Interview({
    required this.id,
    required this.projectId,
    required this.intervieweeAlias,
    required this.notes,
    required this.heldAt,
    this.conclusion,
  });

  final String id;
  final String projectId;
  final String intervieweeAlias;
  final String notes;
  final String? conclusion;
  final DateTime heldAt;
}

abstract final class FieldNoteRules {
  static const maxAliasLength = 60;
  static const maxNotesLength = 4000;
  static const maxShortLength = 500;
  static const maxLinkLength = 500;
}
