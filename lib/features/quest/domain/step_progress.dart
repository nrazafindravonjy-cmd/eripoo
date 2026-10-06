import '../../../content/progress_state.dart';

export '../../../content/progress_state.dart' show StepStatus;

class StepProgress {
  const StepProgress({
    required this.questId,
    required this.stepId,
    required this.status,
    this.startedAt,
    this.completedAt,
    this.deferredUntil,
  });

  final String questId;
  final String stepId;
  final StepStatus status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? deferredUntil;
}
