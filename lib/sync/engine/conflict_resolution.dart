import '../../data/local/entity_types.dart';
import '../../features/quest/domain/step_progress.dart';

/// How concurrent versions of an entity type are reconciled
/// (docs/OFFLINE_SYNC.md §6).
enum EntityFamily { editable, appendOnly, progress }

EntityFamily familyOf(String entityType) => switch (entityType) {
  EntityTypes.projectRevision ||
  EntityTypes.conclusion ||
  EntityTypes.decision ||
  EntityTypes.conflictCopy => EntityFamily.appendOnly,
  EntityTypes.stepProgress => EntityFamily.progress,
  _ => EntityFamily.editable,
};

/// Result of reconciling a local version (with unsent changes) and a
/// remote version of the same entity.
class MergeOutcome {
  const MergeOutcome({required this.merged, this.setAside});

  /// The version kept on this device, sent back to the server.
  final Map<String, Object?> merged;

  /// The version not kept, saved as a conflict copy (never silently lost).
  /// Null when nothing was lost.
  final Map<String, Object?>? setAside;
}

/// Fields that describe bookkeeping, not content.
const _metaFields = {'createdAt', 'updatedAt', 'deletedAt'};

bool _sameContent(Map<String, Object?> a, Map<String, Object?> b) {
  final keys = {...a.keys, ...b.keys}.difference(_metaFields);
  return keys.every((k) => a[k] == b[k]);
}

int? _maxInt(Object? a, Object? b) {
  if (a == null) return b as int?;
  if (b == null) return a as int;
  return (a as int) > (b as int) ? a : b;
}

int? _minInt(Object? a, Object? b) {
  if (a == null) return b as int?;
  if (b == null) return a as int;
  return (a as int) < (b as int) ? a : b;
}

/// Pure and deterministic: no clock, no device time is used to decide.
MergeOutcome resolveConflict({
  required String entityType,
  required Map<String, Object?> local,
  required Map<String, Object?> remote,
}) {
  switch (familyOf(entityType)) {
    case EntityFamily.progress:
      final localStatus = StepStatus.values.byName(local['status']! as String);
      final remoteStatus = StepStatus.values.byName(
        remote['status']! as String,
      );
      // The most advanced status wins; on a tie, this device's choice.
      final status = remoteStatus.rank > localStatus.rank
          ? remoteStatus
          : localStatus;
      return MergeOutcome(
        merged: {
          ...local,
          'status': status.name,
          'startedAt': _minInt(local['startedAt'], remote['startedAt']),
          'completedAt': _maxInt(local['completedAt'], remote['completedAt']),
          // The return date belongs to the side whose status won.
          'deferredUntil': status == localStatus
              ? local['deferredUntil']
              : remote['deferredUntil'],
          'updatedAt': _maxInt(local['updatedAt'], remote['updatedAt']),
        },
      );

    case EntityFamily.appendOnly:
    case EntityFamily.editable:
      final localDeleted = local['deletedAt'] != null;
      final remoteDeleted = remote['deletedAt'] != null;
      if (localDeleted != remoteDeleted) {
        // Deletion wins, and the trash keeps the edited content: the side
        // that was not deleted is the one that was edited.
        final edited = localDeleted ? remote : local;
        final deletion = localDeleted ? local : remote;
        final merged = {...edited, 'deletedAt': deletion['deletedAt']};
        return MergeOutcome(
          merged: merged,
          setAside: _sameContent(deletion, edited) ? null : deletion,
        );
      }
      // This device's version is kept; the other one is set aside.
      return MergeOutcome(
        merged: local,
        setAside: _sameContent(local, remote) ? null : remote,
      );
  }
}
