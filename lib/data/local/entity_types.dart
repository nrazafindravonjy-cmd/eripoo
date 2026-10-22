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
  static const answer = 'answer';
  static const missionInstance = 'mission_instance';
  static const hypothesis = 'hypothesis';
  static const experiment = 'experiment';
  static const experimentHypothesis = 'experiment_hypothesis';
  static const result = 'result';
  static const evidence = 'evidence';
  static const conclusion = 'conclusion';
  static const decision = 'decision';
  static const observation = 'observation';
  static const interview = 'interview';
  static const media = 'media';
  static const toolUnlock = 'tool_unlock';
  static const competitor = 'competitor';
  static const financeItem = 'finance_item';
  static const financePlan = 'finance_plan';

  static const all = [
    profile,
    fact,
    project,
    projectSection,
    projectRevision,
    stepProgress,
    answer,
    missionInstance,
    hypothesis,
    experiment,
    experimentHypothesis,
    result,
    evidence,
    conclusion,
    decision,
    observation,
    interview,
    media,
    toolUnlock,
    competitor,
    financeItem,
    financePlan,
    conflictCopy,
  ];
}
