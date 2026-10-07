// The journey reads the project's research through count rules (statuses
// and types only): quest 4 of the real pack completes when the work is in
// the Project tab. Fictitious data.
import 'dart:async';
import 'dart:convert';

import 'package:eripoo/content/content_pack.dart';
import 'package:eripoo/content/json_reader.dart';
import 'package:eripoo/content/planner.dart';
import 'package:eripoo/content/progress_state.dart';
import 'package:eripoo/content/rules.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/hypotheses/application/research_service.dart';
import 'package:eripoo/features/hypotheses/domain/research.dart';
import 'package:eripoo/features/quest/application/journey_service.dart';
import 'package:eripoo/features/quest/data/progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/journey_overrides.dart';
import '../../helpers/test_database.dart';

const project = '0192f2a0-0000-7000-8000-0000000000aa';

void main() {
  test('count rules on records: by status, category, kind; never text', () {
    final pack = ContentPack.parse(
      jsonEncode({
        'format': 1,
        'pack_id': 'base',
        'version': '1',
        'min_app_version': 1,
        'block_types': ['text'],
        'quests': [
          {
            'id': 'q01',
            'order': 1,
            'maturity': 'validation',
            'title': {'fr': 'Q'},
            'summary': {'fr': 'S'},
            'steps': [
              {
                'id': 'q01.s01',
                'type': 'act',
                'title': {'fr': 'T'},
                'blocks': [
                  {
                    'id': 'b',
                    'type': 'text',
                    'body': {'fr': 'B'},
                  },
                ],
                'available_when': {
                  'all': [
                    {
                      'count': 'hypotheses',
                      'where': {'status': 'validated', 'category': 'price'},
                      'gte': 1,
                    },
                    {
                      'count': 'evidences',
                      'where': {'kind': 'sale'},
                      'gte': 2,
                    },
                    {'count': 'interviews', 'gte': 1},
                  ],
                },
              },
            ],
          },
        ],
      }),
    );
    StepStatus statusWith(Map<String, List<Map<String, String>>> records) =>
        plan(
          PlannerInput(pack: pack, now: DateTime.utc(2026), records: records),
        ).step('q01.s01')!.status;

    final enough = {
      'hypotheses': [
        {'status': 'validated', 'category': 'price'},
      ],
      'evidences': [
        {'kind': 'sale'},
        {'kind': 'sale'},
        {'kind': 'note'},
      ],
      'interviews': [<String, String>{}],
    };
    expect(statusWith(enough), StepStatus.available);
    expect(
      statusWith({
        ...enough,
        'hypotheses': [
          {'status': 'validated', 'category': 'customer'},
        ],
      }),
      StepStatus.locked,
    );
    expect(statusWith({...enough, 'interviews': []}), StepStatus.locked);
    expect(statusWith(const {}), StepStatus.locked);
    // Counting by a text field is refused when the pack is read.
    expect(
      () => Rule.read(
        JsonReader({
          'count': 'hypotheses',
          'where': {'statement': 'savon'},
          'gte': 1,
        }),
      ),
      throwsA(isA<ContentFormatException>()),
    );
  });

  group('quest 4 of the real pack', () {
    late AppDatabase db;
    late JourneyService journey;
    late ResearchService research;
    setUp(() async {
      db = memoryDatabase();
      final pack = basePack();
      journey = JourneyService(pack: pack, db: db);
      research = ResearchService(db);
      // Diagnostic and quests 1–3 done: quest 4 is open.
      final progress = ProgressRepository(db);
      for (final step in pack.steps.where((s) => !s.id.startsWith('q04'))) {
        await progress.setStatus(
          pack.questOfStep(step.id)!.id,
          step.id,
          StepStatus.completed,
        );
      }
      await journey.complete('q04.s01');
    });
    tearDown(() => db.close());

    test('each step completes when the project holds the work', () async {
      expect(await journey.complete('q04.s02'), isA<ConditionNotMet>());
      final h = await research.createHypothesis(
        projectId: project,
        statement: 'Les vendeuses commanderaient du savon livré.',
        category: HypothesisCategory.customer,
      );
      expect(await journey.complete('q04.s02'), isA<StepCompleted>());

      expect(await journey.complete('q04.s03'), isA<ConditionNotMet>());
      final e = await research.planExperiment(
        projectId: project,
        method: ExperimentMethod.preSale,
        plan: 'Proposer à 10 vendeuses.',
        hypothesisIds: [h.id],
        successCriterion: '6 commandes sur 10.',
      );
      expect(await journey.complete('q04.s03'), isA<ConditionNotMet>());
      await research.startExperiment(e.id);
      expect(await journey.complete('q04.s03'), isA<StepCompleted>());

      expect(await journey.complete('q04.s04'), isA<ConditionNotMet>());
      final r = await research.recordResult(
        e.id,
        summary: '3 commandes',
        yes: 3,
        total: 10,
      );
      await research.addEvidence(
        projectId: project,
        subject: EvidenceSubject.result,
        subjectId: r.id,
        kind: EvidenceKind.sale,
        amountMga: 4500,
      );
      await research.conclude(
        h.id,
        outcome: HypothesisStatus.invalidated,
        statement: 'Elles préfèrent acheter le dimanche.',
        confidenceAfter: 2,
      );
      expect(await journey.complete('q04.s04'), isA<StepCompleted>());
      final plan = await journey.currentPlan();
      expect(
        plan.quests.singleWhere((q) => q.quest.id == 'q04').state,
        QuestState.completed,
      );
    });

    test('the plan follows research changes (stream)', () async {
      final plans = <JourneyPlan>[];
      final first = Completer<void>();
      final second = Completer<void>();
      final sub = journey.watchPlan().listen((p) {
        plans.add(p);
        if (plans.length == 1) first.complete();
        if (plans.length == 2) second.complete();
      });
      await first.future;
      await research.createHypothesis(projectId: project, statement: 'H');
      await second.future.timeout(const Duration(seconds: 5));
      await sub.cancel();
      expect(plans.last.step('q04.s02')!.status, StepStatus.available);
    });
  });
}
