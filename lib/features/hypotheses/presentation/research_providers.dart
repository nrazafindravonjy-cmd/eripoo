import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../security/key_manager.dart';
import '../../media/application/photo_source.dart';
import '../../media/data/media_store.dart';
import '../../project/data/project_repository.dart';
import '../../project/domain/project.dart';
import '../../quest/presentation/journey_providers.dart';
import '../application/research_service.dart';
import '../domain/research.dart';

final researchServiceProvider = Provider<ResearchService>((ref) {
  final pack = ref.watch(contentPackProvider);
  return ResearchService(
    ref.watch(appDatabaseProvider),
    questOfStep: (stepId) => pack.questOfStep(stepId)?.id,
  );
});

/// Encrypted photos, with the media sub-key of this device's data key.
final mediaStoreProvider = Provider<MediaStore>((ref) {
  final services = ref.watch(appServicesProvider);
  final keys = DataKeys(services.crypto, services.keys.dataKey);
  ref.onDispose(keys.dispose);
  return MediaStore(
    db: ref.watch(appDatabaseProvider),
    crypto: services.crypto,
    key: keys.media,
    umkVersion: services.keys.dataKeyVersion,
    dir: services.mediaDirectory,
  );
});

final photoSourceProvider = Provider<PhotoSource>((ref) => SystemPhotoSource());

/// Ticks on every change of the research tables: screens re-read.
final _researchTick = StreamProvider<int>((ref) {
  var tick = 0;
  return ref.watch(researchServiceProvider).watchChanges().map((_) => ++tick);
});

final _sectionTick = StreamProvider<int>((ref) {
  var tick = 0;
  return ProjectRepository(ref.watch(appDatabaseProvider))
      .watchSectionChanges()
      .map((_) => ++tick);
});

final hypothesesProvider = FutureProvider.family<List<Hypothesis>, String>((
  ref,
  projectId,
) {
  ref.watch(_researchTick);
  return ref.watch(researchServiceProvider).hypothesesOf(projectId);
});

/// Everything shown on a hypothesis' screen.
class HypothesisDetail {
  const HypothesisDetail({
    required this.hypothesis,
    required this.experiments,
    required this.results,
    required this.evidences,
    required this.conclusions,
    required this.decisions,
    required this.facts,
    this.child,
  });

  final Hypothesis hypothesis;
  final List<Experiment> experiments;

  /// By experiment id.
  final Map<String, List<ExperimentResult>> results;

  /// By subject id (experiments and results).
  final Map<String, List<Evidence>> evidences;
  final List<Conclusion> conclusions;
  final List<Decision> decisions;
  final TestFacts facts;

  /// The version created from this one, if any.
  final Hypothesis? child;
}

final hypothesisDetailProvider =
    FutureProvider.family<HypothesisDetail?, String>((ref, id) async {
      ref.watch(_researchTick);
      final s = ref.watch(researchServiceProvider);
      final h = await s.hypothesis(id);
      if (h == null) return null;
      final experiments = await s.experimentsFor(id);
      final results = {
        for (final e in experiments) e.id: await s.resultsOf(e.id),
      };
      final evidences = <String, List<Evidence>>{
        for (final e in experiments)
          e.id: await s.evidencesOf(EvidenceSubject.experiment, e.id),
        for (final r in results.values.expand((r) => r))
          r.id: await s.evidencesOf(EvidenceSubject.result, r.id),
      };
      final decisions = await s.decisionsOf(id);
      final childId = decisions
          .map((d) => d.newHypothesisId)
          .whereType<String>()
          .lastOrNull;
      return HypothesisDetail(
        hypothesis: h,
        experiments: experiments,
        results: results,
        evidences: evidences,
        conclusions: await s.conclusionsOf(id),
        decisions: decisions,
        facts: await s.testFacts(id),
        child: childId == null ? null : await s.hypothesis(childId),
      );
    });

class FieldNotes {
  const FieldNotes(this.observations, this.interviews, this.evidences);
  final List<Observation> observations;
  final List<Interview> interviews;

  /// By observation or interview id.
  final Map<String, List<Evidence>> evidences;

  int get count => observations.length + interviews.length;
}

final fieldNotesProvider = FutureProvider.family<FieldNotes, String>((
  ref,
  projectId,
) async {
  ref.watch(_researchTick);
  final s = ref.watch(researchServiceProvider);
  final observations = await s.observationsOf(projectId);
  final interviews = await s.interviewsOf(projectId);
  return FieldNotes(observations, interviews, {
    for (final o in observations)
      o.id: await s.evidencesOf(EvidenceSubject.observation, o.id),
    for (final i in interviews)
      i.id: await s.evidencesOf(EvidenceSubject.interview, i.id),
  });
});

final projectSectionsProvider =
    FutureProvider.family<Map<String, ProjectSection>, String>((
      ref,
      projectId,
    ) {
      ref.watch(_sectionTick);
      return ProjectRepository(ref.watch(appDatabaseProvider))
          .sections(projectId);
    });

final projectHistoryProvider =
    FutureProvider.family<List<ProjectRevision>, String>((ref, projectId) {
      ref.watch(_sectionTick);
      return ProjectRepository(ref.watch(appDatabaseProvider))
          .history(projectId);
    });

/// Text for a refused rule (never shows user content).
String guardMessage(AppLocalizations l10n, GuardFailure failure) =>
    switch (failure) {
      GuardFailure.noRunningExperiment => l10n.guardNoRunningExperiment,
      GuardFailure.noSuccessCriterion => l10n.guardNoSuccessCriterion,
      GuardFailure.criterionLocked => l10n.guardCriterionLocked,
      GuardFailure.noResult => l10n.guardNoResult,
      GuardFailure.noEvidence => l10n.guardNoEvidence,
      GuardFailure.experimentWithoutResult => l10n.guardExperimentWithoutResult,
      GuardFailure.notEditable => l10n.guardNotEditable,
      GuardFailure.decisionNotAllowed => l10n.guardDecisionNotAllowed,
      GuardFailure.invalidConfidence => l10n.guardInvalidConfidence,
      GuardFailure.invalidText => l10n.guardInvalidText,
      GuardFailure.invalidMetrics => l10n.guardInvalidMetrics,
      GuardFailure.experimentNotStarted => l10n.guardExperimentNotStarted,
      GuardFailure.incompleteEvidence => l10n.guardIncompleteEvidence,
      GuardFailure.notFound => l10n.guardNotFound,
    };

/// Runs [action]; a refused rule or move is shown as a message, never as a
/// crash. Returns true when it succeeded.
Future<bool> runGuarded(
  BuildContext context,
  Future<void> Function() action,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  String? message;
  try {
    await action();
    return true;
  } on GuardViolation catch (e) {
    message = guardMessage(l10n, e.failure);
  } on InvalidHypothesisTransition {
    message = l10n.guardDecisionNotAllowed;
  } on InvalidExperimentTransition {
    message = l10n.guardDecisionNotAllowed;
  } on MediaTooLarge {
    message = l10n.evidencePhotoTooLarge;
  } on UnsupportedMedia {
    message = l10n.evidencePhotoUnreadable;
  }
  messenger?.showSnackBar(SnackBar(content: Text(message)));
  return false;
}

String statusLabel(AppLocalizations l10n, HypothesisStatus s) => switch (s) {
  HypothesisStatus.draft => l10n.statusDraft,
  HypothesisStatus.toTest => l10n.statusToTest,
  HypothesisStatus.testing => l10n.statusTesting,
  HypothesisStatus.validated => l10n.statusValidated,
  HypothesisStatus.invalidated => l10n.statusInvalidated,
  HypothesisStatus.inconclusive => l10n.statusInconclusive,
  HypothesisStatus.abandoned => l10n.statusAbandoned,
};

String categoryLabel(AppLocalizations l10n, HypothesisCategory c) =>
    switch (c) {
      HypothesisCategory.problem => l10n.categoryProblem,
      HypothesisCategory.customer => l10n.categoryCustomer,
      HypothesisCategory.solution => l10n.categorySolution,
      HypothesisCategory.price => l10n.categoryPrice,
      HypothesisCategory.channel => l10n.categoryChannel,
      HypothesisCategory.other => l10n.categoryOther,
    };

String methodLabel(AppLocalizations l10n, ExperimentMethod m) => switch (m) {
  ExperimentMethod.interview => l10n.methodInterview,
  ExperimentMethod.observation => l10n.methodObservation,
  ExperimentMethod.prototype => l10n.methodPrototype,
  ExperimentMethod.priceTest => l10n.methodPriceTest,
  ExperimentMethod.preSale => l10n.methodPreSale,
  ExperimentMethod.freeTrial => l10n.methodFreeTrial,
  ExperimentMethod.other => l10n.methodOther,
};

String experimentStatusLabel(AppLocalizations l10n, ExperimentStatus s) =>
    switch (s) {
      ExperimentStatus.planned => l10n.experimentStatusPlanned,
      ExperimentStatus.running => l10n.experimentStatusRunning,
      ExperimentStatus.done => l10n.experimentStatusDone,
      ExperimentStatus.cancelled => l10n.experimentStatusCancelled,
    };

String decisionLabel(AppLocalizations l10n, DecisionKind d) => switch (d) {
  DecisionKind.keepGoing => l10n.decisionKeepGoing,
  DecisionKind.modify => l10n.decisionModify,
  DecisionKind.testMore => l10n.decisionTestMore,
  DecisionKind.abandon => l10n.decisionAbandon,
  DecisionKind.goBack => l10n.decisionGoBack,
};

String evidenceKindLabel(AppLocalizations l10n, EvidenceKind k) => switch (k) {
  EvidenceKind.note => l10n.evidenceKindNote,
  EvidenceKind.photo => l10n.evidenceKindPhoto,
  EvidenceKind.link => l10n.evidenceKindLink,
  EvidenceKind.number => l10n.evidenceKindNumber,
  EvidenceKind.sale => l10n.evidenceKindSale,
};

String maturityLabel(AppLocalizations l10n, MaturityStage s) => switch (s) {
  MaturityStage.exploration => l10n.maturityExploration,
  MaturityStage.validation => l10n.maturityValidation,
  MaturityStage.construction => l10n.maturityConstruction,
  MaturityStage.preparation => l10n.maturityPreparation,
  MaturityStage.launch => l10n.maturityLaunch,
};
