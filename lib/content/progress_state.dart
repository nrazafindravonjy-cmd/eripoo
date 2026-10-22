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

  bool get isDone => this == completed || this == fastTracked;
}

/// Derived state of a whole quest.
enum QuestState { notStarted, inProgress, completed }

/// Mission instance life cycle (docs/PRODUCT_ARCHITECTURE.md §5).
enum MissionStatus {
  proposed,
  accepted,
  inProgress,
  submitted,
  completed,
  abandoned;

  bool get isOpen => this != completed && this != abandoned;
}
