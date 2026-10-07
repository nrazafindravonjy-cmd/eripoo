// Hypothesis → experiment → result → evidence → conclusion → decision,
// through the service and a real (in-memory) database. Fictitious data.
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/data/local/encrypted_database.dart';
import 'package:eripoo/data/local/entity_types.dart';
import 'package:eripoo/features/hypotheses/application/research_service.dart';
import 'package:eripoo/features/hypotheses/domain/research.dart';
import 'package:eripoo/features/quest/data/progress_repository.dart';
import 'package:eripoo/features/quest/domain/step_progress.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

const project = '0192f2a0-0000-7000-8000-000000000001';

Matcher refusedWith(GuardFailure failure) =>
    throwsA(isA<GuardViolation>().having((e) => e.failure, 'failure', failure));

void main() {
  late AppDatabase db;
  late ResearchService research;
  setUp(() {
    db = memoryDatabase();
    research = ResearchService(
      db,
      questOfStep: (step) => step.split('.').first,
    );
  });
  tearDown(() => db.close());

  Future<Hypothesis> hypothesis([
    String text =
        'Les vendeuses manquent '
        'de temps pour acheter du savon.',
  ]) => research.createHypothesis(
    projectId: project,
    statement: text,
    category: HypothesisCategory.problem,
    confidenceBefore: 3,
    sourceStepId: 'q01.s02',
  );

  Future<HypothesisStatus> statusOf(String id) async =>
      (await research.hypothesis(id))!.status;

  /// A hypothesis tested by a running experiment with one result and one
  /// piece of evidence.
  Future<(Hypothesis, Experiment)> tested() async {
    final h = await hypothesis();
    final e = await research.planExperiment(
      projectId: project,
      method: ExperimentMethod.interview,
      plan: 'Parler à 5 vendeuses du marché.',
      hypothesisIds: [h.id],
      successCriterion: 'Au moins 3 sur 5 en parlent sans qu’on demande.',
      sampleTarget: 5,
    );
    await research.startExperiment(e.id);
    final r = await research.recordResult(
      e.id,
      summary: '4 vendeuses sur 5 en parlent.',
      yes: 4,
      total: 5,
    );
    await research.addEvidence(
      projectId: project,
      subject: EvidenceSubject.result,
      subjectId: r.id,
      kind: EvidenceKind.note,
      body: 'Notes prises au marché, sans nom.',
    );
    return (h, e);
  }

  test('a new hypothesis is a draft, editable, marked for sync', () async {
    final h = await hypothesis();
    expect(h.status, HypothesisStatus.draft);
    await research.editHypothesis(h.id, statement: '  Nouvelle version.  ');
    expect((await research.hypothesis(h.id))!.statement, 'Nouvelle version.');
    final pending = await (db.select(
      db.syncMetaEntries,
    )..where((t) => t.entityType.equals(EntityTypes.hypothesis))).get();
    expect(pending.single.changeId, isNotNull);
  });

  test(
    'planning a test makes a draft "to test"; testing needs it to run',
    () async {
      final h = await hypothesis();
      final e = await research.planExperiment(
        projectId: project,
        method: ExperimentMethod.observation,
        plan: 'Observer le marché un samedi matin.',
        hypothesisIds: [h.id],
      );
      expect(await statusOf(h.id), HypothesisStatus.toTest);
      expect(e.status, ExperimentStatus.planned);
      // No criterion: the test cannot start (rule 2).
      await expectLater(
        research.startExperiment(e.id),
        refusedWith(GuardFailure.noSuccessCriterion),
      );
      await research.editExperiment(
        e.id,
        successCriterion:
            'Au moins 6 personnes sur 10 attendent plus de '
            '10 minutes.',
      );
      await research.startExperiment(e.id);
      expect(await statusOf(h.id), HypothesisStatus.testing);
      final started = (await research.experiment(e.id))!;
      expect(started.criterionLockedAt, isNotNull);
      // The criterion is now locked; the plan can still be clarified.
      await expectLater(
        research.editExperiment(e.id, successCriterion: 'Autre chose'),
        refusedWith(GuardFailure.criterionLocked),
      );
      await research.editExperiment(e.id, plan: 'Observer deux samedis.');
    },
  );

  test('a tested hypothesis cannot be edited in place (rule 4)', () async {
    final (h, _) = await tested();
    await expectLater(
      research.editHypothesis(h.id, statement: 'Changé'),
      refusedWith(GuardFailure.notEditable),
    );
  });

  test('results only on a started test; done needs a result', () async {
    final h = await hypothesis();
    final e = await research.planExperiment(
      projectId: project,
      method: ExperimentMethod.priceTest,
      plan: 'Proposer le savon à 1 500 Ar.',
      hypothesisIds: [h.id],
      successCriterion: '5 ventes sur 10 propositions.',
    );
    await expectLater(
      research.recordResult(e.id, summary: 'Trop tôt'),
      refusedWith(GuardFailure.experimentNotStarted),
    );
    await research.startExperiment(e.id);
    await expectLater(
      research.finishExperiment(e.id),
      refusedWith(GuardFailure.experimentWithoutResult),
    );
    await expectLater(
      research.recordResult(e.id, summary: 'x', yes: 6, total: 5),
      refusedWith(GuardFailure.invalidMetrics),
    );
    await research.recordResult(e.id, summary: '3 ventes', yes: 3, total: 10);
    await research.finishExperiment(e.id);
    expect((await research.experiment(e.id))!.status, ExperimentStatus.done);
  });

  test(
    'validated needs a result and evidence; inconclusive a result',
    () async {
      final h = await hypothesis();
      final e = await research.planExperiment(
        projectId: project,
        method: ExperimentMethod.interview,
        plan: 'Interroger 5 personnes.',
        hypothesisIds: [h.id],
        successCriterion: '3 sur 5.',
      );
      await research.startExperiment(e.id);
      await expectLater(
        research.conclude(
          h.id,
          outcome: HypothesisStatus.validated,
          statement: 'Oui',
          confidenceAfter: 4,
        ),
        refusedWith(GuardFailure.noResult),
      );
      final r = await research.recordResult(e.id, summary: '4 sur 5');
      await expectLater(
        research.conclude(
          h.id,
          outcome: HypothesisStatus.validated,
          statement: 'Oui',
          confidenceAfter: 4,
        ),
        refusedWith(GuardFailure.noEvidence),
      );
      await research.addEvidence(
        projectId: project,
        subject: EvidenceSubject.result,
        subjectId: r.id,
        kind: EvidenceKind.number,
        numberValue: 4,
      );
      final c = await research.conclude(
        h.id,
        outcome: HypothesisStatus.validated,
        statement: 'Le manque de temps est réel.',
        confidenceAfter: 4,
        experimentId: e.id,
      );
      expect(c.outcome, HypothesisStatus.validated);
      expect(await statusOf(h.id), HypothesisStatus.validated);
      // Nothing moves a validated hypothesis any more.
      await expectLater(
        research.abandon(h.id),
        throwsA(isA<InvalidHypothesisTransition>()),
      );
    },
  );

  test('evidence must be complete for its kind', () async {
    for (final (kind, body, number, amount, media)
        in <(EvidenceKind, String?, double?, int?, String?)>[
          (EvidenceKind.note, '  ', null, null, null),
          (EvidenceKind.link, null, null, null, null),
          (EvidenceKind.number, null, double.nan, null, null),
          (EvidenceKind.sale, null, null, -1, null),
          (EvidenceKind.photo, 'légende', null, null, null),
        ]) {
      await expectLater(
        research.addEvidence(
          projectId: project,
          subject: EvidenceSubject.observation,
          subjectId: 'x',
          kind: kind,
          body: body,
          numberValue: number,
          amountMga: amount,
          mediaId: media,
        ),
        refusedWith(GuardFailure.incompleteEvidence),
        reason: kind.name,
      );
    }
    final sale = await research.addEvidence(
      projectId: project,
      subject: EvidenceSubject.observation,
      subjectId: 'x',
      kind: EvidenceKind.sale,
      amountMga: 15000,
    );
    expect(sale.amountMga, 15000);
  });

  group('decisions', () {
    Future<Hypothesis> concluded(HypothesisStatus outcome) async {
      final (h, e) = await tested();
      await research.finishExperiment(e.id);
      await research.conclude(
        h.id,
        outcome: outcome,
        statement: 'Ce que je pense maintenant.',
        confidenceAfter: 3,
        experimentId: e.id,
      );
      return h;
    }

    test(
      '"modify" creates a linked new version; the old one is kept',
      () async {
        final h = await concluded(HypothesisStatus.invalidated);
        final d = await research.decide(
          h.id,
          kind: DecisionKind.modify,
          rationale: 'Le vrai problème est l’eau, pas le savon.',
          newStatement: 'Les vendeuses manquent d’eau le matin.',
        );
        final child = (await research.hypothesis(d.newHypothesisId!))!;
        expect(child.parentHypothesisId, h.id);
        expect(child.status, HypothesisStatus.draft);
        expect(child.sourceStepId, h.sourceStepId);
        expect(await statusOf(h.id), HypothesisStatus.invalidated);
        await expectLater(
          research.decide(h.id, kind: DecisionKind.modify, rationale: 'x'),
          refusedWith(GuardFailure.invalidText),
        );
      },
    );

    test('"test more" on inconclusive: to test, then testing again', () async {
      final h = await concluded(HypothesisStatus.inconclusive);
      await research.decide(
        h.id,
        kind: DecisionKind.testMore,
        rationale: 'Trop peu de personnes.',
      );
      expect(await statusOf(h.id), HypothesisStatus.toTest);
      final e2 = await research.planExperiment(
        projectId: project,
        method: ExperimentMethod.interview,
        plan: 'Interroger 10 autres personnes.',
        hypothesisIds: [h.id],
        successCriterion: '6 sur 10.',
      );
      await research.startExperiment(e2.id);
      expect(await statusOf(h.id), HypothesisStatus.testing);
    });

    test('"abandon" only on inconclusive; refused on validated', () async {
      final h = await concluded(HypothesisStatus.validated);
      await expectLater(
        research.decide(h.id, kind: DecisionKind.abandon, rationale: 'x'),
        refusedWith(GuardFailure.decisionNotAllowed),
      );
      final h2 = await concluded(HypothesisStatus.inconclusive);
      await research.decide(
        h2.id,
        kind: DecisionKind.abandon,
        rationale: 'Pas prioritaire.',
      );
      expect(await statusOf(h2.id), HypothesisStatus.abandoned);
    });

    test('"go back" reopens the step the hypothesis came from', () async {
      final progress = ProgressRepository(db);
      await progress.setStatus('q01', 'q01.s02', StepStatus.completed);
      final h = await concluded(HypothesisStatus.invalidated);
      await research.decide(
        h.id,
        kind: DecisionKind.goBack,
        rationale: 'Je dois revoir le problème.',
      );
      expect((await progress.get('q01.s02'))!.status, StepStatus.inProgress);
    });

    test('the journal is append-only and keeps the order', () async {
      final h = await concluded(HypothesisStatus.validated);
      await research.decide(
        h.id,
        kind: DecisionKind.keepGoing,
        rationale: 'On continue.',
      );
      await research.decide(
        h.id,
        kind: DecisionKind.goBack,
        rationale: 'Revoir la cible.',
      );
      final journal = await research.decisionsOf(h.id);
      expect(journal.map((d) => d.kind), [
        DecisionKind.keepGoing,
        DecisionKind.goBack,
      ]);
      final rows = await db.select(db.decisions).get();
      expect(rows.map((r) => r.decision), ['continue', 'go_back']);
    });
  });

  test('cancelling the only running test sends the hypothesis back', () async {
    final h = await hypothesis();
    final e = await research.planExperiment(
      projectId: project,
      method: ExperimentMethod.prototype,
      plan: 'Montrer un emballage.',
      hypothesisIds: [h.id],
      successCriterion: '3 personnes veulent l’acheter.',
    );
    await research.startExperiment(e.id);
    await research.cancelExperiment(e.id);
    expect(await statusOf(h.id), HypothesisStatus.toTest);
    await research.abandon(h.id);
    expect(await statusOf(h.id), HypothesisStatus.abandoned);
  });

  test('field notes: pseudonym and text only, validated', () async {
    final i = await research.addInterview(
      projectId: project,
      alias: '  Vendeuse A  ',
      notes: 'Achète le savon le dimanche.',
    );
    expect(i.intervieweeAlias, 'Vendeuse A');
    await expectLater(
      research.addInterview(projectId: project, alias: 'x' * 61, notes: 'n'),
      refusedWith(GuardFailure.invalidText),
    );
    final o = await research.addObservation(
      projectId: project,
      description: 'File d’attente à la borne-fontaine.',
      context: 'Samedi matin',
    );
    expect(o.supposedProblem, isNull);
    expect(await research.interviewsOf(project), hasLength(1));
    expect(await research.observationsOf(project), hasLength(1));
  });

  test('random walks keep every invariant (300 walks × 25 steps)', () async {
    // Each walk tries random operations; refused ones must leave no
    // trace, accepted ones must keep the invariants below.
    for (var seed = 0; seed < 300; seed++) {
      final random = Random(seed);
      final walkDb = memoryDatabase();
      final s = ResearchService(walkDb);
      final hyps = <String>[];
      final exps = <String>[];
      final history = <String, List<HypothesisStatus>>{};
      var decisions = 0;

      Future<void> attempt(Future<void> Function() op) async {
        try {
          await op();
        } on GuardViolation {
          // refused by a rule: fine
        } on InvalidHypothesisTransition {
          // refused by the machine: fine
        } on InvalidExperimentTransition {
          // idem
        }
      }

      T pick<T>(List<T> list) => list[random.nextInt(list.length)];

      for (var step = 0; step < 25; step++) {
        final op = random.nextInt(10);
        if (hyps.isEmpty || op == 0) {
          final h = await s.createHypothesis(
            projectId: project,
            statement: 'Hypothèse $step',
          );
          hyps.add(h.id);
          continue;
        }
        switch (op) {
          case 1:
            await attempt(
              () async => exps.add(
                (await s.planExperiment(
                  projectId: project,
                  method: ExperimentMethod.interview,
                  plan: 'Plan',
                  hypothesisIds: [pick(hyps)],
                  successCriterion: random.nextBool() ? 'Critère' : null,
                )).id,
              ),
            );
          case 2 when exps.isNotEmpty:
            await attempt(() => s.startExperiment(pick(exps)));
          case 3 when exps.isNotEmpty:
            await attempt(() async {
              final r = await s.recordResult(pick(exps), summary: 'Résultat');
              if (random.nextBool()) {
                await s.addEvidence(
                  projectId: project,
                  subject: EvidenceSubject.result,
                  subjectId: r.id,
                  kind: EvidenceKind.note,
                  body: 'Preuve',
                );
              }
            });
          case 4 when exps.isNotEmpty:
            await attempt(() => s.finishExperiment(pick(exps)));
          case 5 when exps.isNotEmpty:
            await attempt(() => s.cancelExperiment(pick(exps)));
          case 6:
            await attempt(
              () => s.conclude(
                pick(hyps),
                outcome: pick([
                  HypothesisStatus.validated,
                  HypothesisStatus.invalidated,
                  HypothesisStatus.inconclusive,
                ]),
                statement: 'Conclusion',
                confidenceAfter: 1 + random.nextInt(5),
              ),
            );
          case 7:
            await attempt(() async {
              await s.decide(
                pick(hyps),
                kind: pick(DecisionKind.values),
                rationale: 'Parce que',
                newStatement: 'Nouvelle version',
              );
              decisions++;
            });
          case 8:
            await attempt(() => s.abandon(pick(hyps)));
          default:
            await attempt(() => s.markToTest(pick(hyps)));
        }

        // ---- invariants after every operation
        for (final h in await s.hypothesesOf(project)) {
          final seen = history.putIfAbsent(h.id, () => []);
          if (seen.isEmpty || seen.last != h.status) {
            if (seen.isNotEmpty) {
              expect(
                HypothesisMachine.canMove(seen.last, h.status),
                isTrue,
                reason: 'seed $seed: ${seen.last} → ${h.status}',
              );
            }
            seen.add(h.status);
          }
          if (!hyps.contains(h.id)) hyps.add(h.id); // versions from modify
          final experiments = await s.experimentsFor(h.id);
          final facts = await s.testFacts(h.id);
          switch (h.status) {
            case HypothesisStatus.testing:
              expect(
                experiments.any(
                  (e) =>
                      e.status == ExperimentStatus.running ||
                      e.status == ExperimentStatus.done,
                ),
                isTrue,
                reason: 'seed $seed: testing without a started test',
              );
            case HypothesisStatus.validated || HypothesisStatus.invalidated:
              expect(facts.results, greaterThan(0), reason: 'seed $seed');
              expect(facts.evidences, greaterThan(0), reason: 'seed $seed');
              expect(await s.conclusionsOf(h.id), isNotEmpty);
            case HypothesisStatus.inconclusive:
              expect(facts.results, greaterThan(0), reason: 'seed $seed');
            default:
          }
        }
        for (final id in exps) {
          final e = (await s.experiment(id))!;
          if (e.status == ExperimentStatus.running ||
              e.status == ExperimentStatus.done) {
            expect(e.successCriterion, isNotNull, reason: 'seed $seed');
            expect(e.criterionLockedAt, isNotNull, reason: 'seed $seed');
          }
          if (e.status == ExperimentStatus.done) {
            expect(await s.resultsOf(id), isNotEmpty, reason: 'seed $seed');
          }
        }
        expect(
          (await walkDb.select(walkDb.decisions).get()).length,
          decisions,
          reason: 'seed $seed: the journal only grows by accepted decisions',
        );
      }
      await walkDb.close();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('a schema v2 database migrates to the current schema without losing '
      'data', () async {
    final dir = Directory.systemTemp.createTempSync('eripoo_migr3');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/db.sqlite');
    final key = Uint8List.fromList(List.generate(32, (i) => 255 - i));
    AppDatabase open() => AppDatabase(
      NativeDatabase(file, setup: (d) => applyDatabaseKey(d, key)),
    );

    final v3 = open();
    await ProgressRepository(v3)
        .setStatus('q01', 'q01.s01', StepStatus.completed);
    for (final table in [
      'hypotheses',
      'experiments',
      'experiment_hypotheses',
      'results',
      'evidences',
      'conclusions',
      'decisions',
      'observations',
      'interviews',
      'media_items',
      'media_uploads', // v4
    ]) {
      await v3.customStatement('drop table $table');
    }
    await v3.customStatement(
      'alter table sync_meta_entries drop column purge_requested', // v5
    );
    await v3.customStatement('drop table tool_unlocks'); // v6
    await v3.customStatement('drop table competitors'); // v6
    await v3.customStatement('pragma user_version = 2');
    await v3.close();

    final migrated = open();
    addTearDown(migrated.close);
    expect(
      (await ProgressRepository(migrated).get('q01.s01'))!.status,
      StepStatus.completed,
    );
    final s = ResearchService(migrated);
    final h = await s.createHypothesis(projectId: project, statement: 'H');
    expect(h.status, HypothesisStatus.draft);
    final version = await migrated
        .customSelect('pragma user_version')
        .getSingle();
    expect(version.data.values.single, migrated.schemaVersion);
  });
}
