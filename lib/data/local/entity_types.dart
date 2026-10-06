/// Names of synchronised entity types. Stored inside encrypted payloads
/// and in `sync_meta`; never change an existing value.
abstract final class EntityTypes {
  static const profile = 'profile';
  static const fact = 'fact';
  static const project = 'project';
  static const projectSection = 'project_section';
  static const projectRevision = 'project_revision';
  static const stepProgress = 'step_progress';
  static const conflictCopy = 'conflict_copy';

  static const all = [
    profile,
    fact,
    project,
    projectSection,
    projectRevision,
    stepProgress,
    conflictCopy,
  ];
}
