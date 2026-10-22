// Points to review: fixed rules over the user's own work, each one
// triggered and cleared; nothing is sent to any AI service. Fictitious data
// only.
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/ai/ai_assistant.dart';
import 'package:eripoo/features/documents/application/project_synthesis.dart';
import 'package:eripoo/features/finance/application/finance_service.dart';
import 'package:eripoo/features/hypotheses/application/research_service.dart';
import 'package:eripoo/features/hypotheses/domain/hypothesis_states.dart';
import 'package:eripoo/features/hypotheses/domain/research.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/features/review/application/review_points.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late String project;
  late FinanceService finance;

  setUp(() async {
    db = memoryDatabase();
    project = (await ProjectRepository(db).create('Savon du quartier')).id;
    finance = FinanceService(db);
  });
  tearDown(() => db.close());

  Future<List<ReviewPoint>> points() async =>
      reviewPoints((await ProjectSynthesisService(db).of(project))!);

  Future<List<ReviewPointKind>> kinds() async => [
    for (final p in await points()) p.kind,
  ];

  Future<void> cost(FinanceKind kind, int amount, [FundingSource? source]) =>
      finance.add(
        projectId: project,
        kind: kind,
        label: 'Ligne',
        amountMga: amount,
        source: source,
      );

  Future<void> plan({int? price, int? first, int? last}) => finance.savePlan(
    project,
    priceMga: price,
    volumeFirst: first,
    volumeLast: last,
  );

  Future<void> section(String key, Map<String, Object?> fields) =>
      ProjectRepository(db)
          .saveSection(projectId: project, sectionKey: key, fields: fields);

  test('an empty project has nothing to review', () async {
    expect(await points(), isEmpty);
  });

  test('a price without any unit cost', () async {
    await plan(price: 2000);
    expect(await kinds(), [ReviewPointKind.priceWithoutCost]);
    await cost(FinanceKind.variableCost, 800);
    expect(await kinds(), isEmpty);
  });

  test('a price below the unit cost, with the two amounts', () async {
    await cost(FinanceKind.variableCost, 1200);
    await cost(FinanceKind.fixedCost, 50000);
    await plan(price: 1000);
    final p = await points();
    expect([for (final x in p) x.kind], [ReviewPointKind.priceBelowCost]);
    expect(p.single.numbers, [1000, 1200]);
    await plan(price: 1500);
    expect(await kinds(), isEmpty);
  });

  test('a price equal to the unit cost never covers the month', () async {
    await cost(FinanceKind.variableCost, 1000);
    await cost(FinanceKind.fixedCost, 50000);
    await plan(price: 1000);
    expect(await kinds(), [ReviewPointKind.breakEvenUnreachable]);
  });

  test('break-even above the sales planned in month 12', () async {
    await cost(FinanceKind.variableCost, 1000);
    await cost(FinanceKind.fixedCost, 100000);
    // 1 000 Ar left per unit: 100 units a month to cover 100 000 Ar.
    await plan(price: 2000, first: 10, last: 60);
    final p = (await points()).where(
      (x) => x.kind == ReviewPointKind.breakEvenAbovePlan,
    );
    expect(p.single.numbers, [100, 60]);
    await plan(price: 2000, first: 10, last: 100);
    expect(await kinds(), isNot(contains(ReviewPointKind.breakEvenAbovePlan)));
  });

  test('money still missing for the cash plan, until it is found', () async {
    await cost(FinanceKind.variableCost, 1000);
    await cost(FinanceKind.investment, 300000);
    await plan(price: 2000, first: 10, last: 50);
    final p = (await points()).where(
      (x) => x.kind == ReviewPointKind.fundingMissing,
    );
    final missing = p.single.numbers.single;
    expect(missing, greaterThan(0));
    await cost(FinanceKind.funding, missing, FundingSource.own);
    expect(await kinds(), isNot(contains(ReviewPointKind.fundingMissing)));
  });

  test('a pitch proof with no validated hypothesis', () async {
    await section('pitch', {'proof': '4 vendeuses sur 5 en veulent.'});
    expect(await kinds(), [ReviewPointKind.proofWithoutTest]);

    final research = ResearchService(db);
    final h = await research.createHypothesis(
      projectId: project,
      statement: 'Les vendeuses achètent du savon chaque semaine.',
      category: HypothesisCategory.customer,
      confidenceBefore: 3,
    );
    final e = await research.planExperiment(
      projectId: project,
      method: ExperimentMethod.interview,
      plan: 'Parler à 5 vendeuses.',
      hypothesisIds: [h.id],
      successCriterion: '3 sur 5.',
      sampleTarget: 5,
    );
    await research.startExperiment(e.id);
    final r = await research.recordResult(
      e.id,
      summary: '4 sur 5.',
      yes: 4,
      total: 5,
    );
    await research.addEvidence(
      projectId: project,
      subject: EvidenceSubject.result,
      subjectId: r.id,
      kind: EvidenceKind.note,
      body: 'Notes sans nom.',
    );
    await research.finishExperiment(e.id);
    await research.conclude(
      h.id,
      outcome: HypothesisStatus.validated,
      statement: 'Elles en achètent.',
      confidenceAfter: 4,
      experimentId: e.id,
    );
    expect(await kinds(), isEmpty);
  });

  test('a solution before knowing who it is for', () async {
    await section('solution', {'first_idea': 'Savon livré au marché'});
    expect(await kinds(), [ReviewPointKind.solutionWithoutCustomers]);
    await section('customers', {'first_guess': 'Vendeuses du marché'});
    expect(await kinds(), isEmpty);
  });

  test('the AI assistant is off: nothing can be sent', () {
    expect(const DisabledAiAssistant().available, isFalse);
  });
}
