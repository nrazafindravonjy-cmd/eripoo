/// Status of a quest step (docs/PRODUCT_ARCHITECTURE.md §3.3).
enum StepStatus {
  locked,
  available,
  inProgress,
  deferred,
  postponed,
  fastTracked,
  completed;

  /// Rank used to merge concurrent progress (docs/OFFLINE_SYNC.md §6): the
  /// most advanced status wins. Deferred/postponed rank with "in progress":
  /// they never undo a completion.
  int get rank => switch (this) {
    locked => 0,
    available => 1,
    inProgress || deferred || postponed => 2,
    fastTracked || completed => 3,
  };
}

class StepProgress {
  const StepProgress({
    required this.questId,
    required this.stepId,
    required this.status,
    this.startedAt,
    this.completedAt,
  });

  final String questId;
  final String stepId;
  final StepStatus status;
  final DateTime? startedAt;
  final DateTime? completedAt;
}
