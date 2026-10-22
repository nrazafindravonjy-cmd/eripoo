import '../../../content/progress_state.dart';

export '../../../content/progress_state.dart' show MissionStatus;

/// A mission instance as stored (its template comes from the content).
class MissionInstance {
  const MissionInstance({
    required this.templateId,
    required this.status,
    this.acceptedAt,
    this.submittedAt,
    this.completedAt,
    this.reflection,
  });

  final String templateId;
  final MissionStatus status;
  final DateTime? acceptedAt;
  final DateTime? submittedAt;
  final DateTime? completedAt;
  final String? reflection;
}

/// The move is not allowed from the current status.
class InvalidMissionTransition implements Exception {
  const InvalidMissionTransition();
}

/// Mission life cycle (docs/PRODUCT_ARCHITECTURE.md §5):
/// proposed → accepted → in_progress → submitted → completed | abandoned.
abstract final class MissionMachine {
  static const _allowed = <MissionStatus, Set<MissionStatus>>{
    MissionStatus.proposed: {MissionStatus.accepted, MissionStatus.abandoned},
    MissionStatus.accepted: {
      MissionStatus.inProgress,
      MissionStatus.submitted,
      MissionStatus.abandoned,
    },
    MissionStatus.inProgress: {
      MissionStatus.submitted,
      MissionStatus.abandoned,
    },
    // Submitted work is completed when the content's rule holds; it can be
    // reopened to add to it.
    MissionStatus.submitted: {
      MissionStatus.completed,
      MissionStatus.inProgress,
      MissionStatus.abandoned,
    },
    MissionStatus.completed: {},
    // An abandoned mission can be taken up again later.
    MissionStatus.abandoned: {MissionStatus.accepted},
  };

  static bool canMove(MissionStatus from, MissionStatus to) =>
      _allowed[from]!.contains(to);

  static void check(MissionStatus from, MissionStatus to) {
    if (!canMove(from, to)) throw const InvalidMissionTransition();
  }
}
