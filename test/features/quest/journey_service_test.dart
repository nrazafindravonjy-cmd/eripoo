import 'dart:convert';

import 'package:eripoo/content/content_pack.dart';
import 'package:eripoo/content/progress_state.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/diagnostic/data/facts_repository.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/features/quest/application/journey_service.dart';
import 'package:eripoo/features/quest/domain/answer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../content/fixture_pack.dart';
import '../../helpers/test_database.dart';

void main() {
  final pack = ContentPack.parse(jsonEncode(fixturePack()));
  late AppDatabase db;
  late TestClock clock;
  late JourneyService journey;

  setUp(() {
    db = memoryDatabase();
    clock = TestClock();
    journey = JourneyService(pack: pack, db: db, clock: clock.call);
  });
  tearDown(() => db.close());

  Future<void> doDiagnostic({String stage = 'vague_idea'}) async {
    await journey.open('diag.s01');
    await journey.saveAnswer(
      'diag.s01',
      'stage',
      Answer(AnswerType.choice, stage),
    );
    await journey.saveAnswer(
      'diag.s01',
      'hours',
      const Answer(AnswerType.number, 5),
    );
    await journey.saveAnswer(
      'diag.s01',
      'name',
      const Answer(AnswerType.text, 'Mofo gasy'),
    );
    expect(await journey.complete('diag.s01'), isA<StepCompleted>());
  }

  test('the diagnostic writes facts and creates the project', () async {
    expect((await journey.currentPlan()).next!.step.id, 'diag.s01');
    await doDiagnostic();
    final facts = await FactsRepository(db).all();
    expect(facts['diag.idea_stage'], 'vague_idea');
    expect(facts['diag.weekly_hours'], 5);
    final projects = await ProjectRepository(db).watchActive().first;
    expect(projects.single.title, 'Mofo gasy');
    expect((await journey.currentPlan()).next!.step.id, 'q01.s01');
  });

  test('a step cannot finish with required questions unanswered', () async {
    await doDiagnostic();
    await journey.open('q01.s02');
    final r = await journey.complete('q01.s02');
    expect(r, isA<MissingAnswers>());
    expect((r as MissingAnswers).blockIds, ['problem']);
  });

  test('outputs fill the project section, tracked in its history', () async {
    await doDiagnostic();
    await journey.complete('q01.s01');
    await journey.saveAnswer(
      'q01.s02',
      'problem',
      const Answer(AnswerType.text, 'Pas de pain le soir'),
    );
    expect(await journey.complete('q01.s02'), isA<StepCompleted>());
    final projects = ProjectRepository(db);
    final project = (await projects.watchActive().first).single;
    final section = await projects.section(project.id, 'problem');
    expect(section!.fields['statement'], 'Pas de pain le soir');

    // Redoing the step changes the answer: history keeps both.
    await journey.saveAnswer(
      'q01.s02',
      'problem',
      const Answer(AnswerType.text, 'Pas de riz le soir'),
    );
    await journey.complete('q01.s02');
    final history = await projects.history(project.id);
    expect(history.map((r) => r.newValue), contains('Pas de riz le soir'));
  });

  test(
    'a step waiting for its mission completes once the mission is done',
    () async {
      await doDiagnostic();
      await journey.complete('q01.s01');
      await journey.saveAnswer(
        'q01.s02',
        'problem',
        const Answer(AnswerType.text, 'x'),
      );
      await journey.complete('q01.s02');
      expect(await journey.complete('q01.s03'), isA<ConditionNotMet>());

      await journey.acceptMission('m.observe');
      expect(
        await journey.submitMission(
          'm.observe',
          'Trois boutiques fermées à 18h',
        ),
        MissionStatus.completed,
      );
      expect(await journey.complete('q01.s03'), isA<StepCompleted>());
      final plan = await journey.currentPlan();
      expect(plan.quests.first.state, QuestState.completed);
      expect(plan.next!.step.id, 'q02.s01');
    },
  );

  test('skip for now and come back later', () async {
    await doDiagnostic();
    await journey.complete('q01.s01');
    await journey.skipForNow('q01.s02');
    var plan = await journey.currentPlan();
    expect(plan.step('q01.s02')!.status, StepStatus.deferred);
    expect(plan.next!.step.id, 'q01.s03');

    clock.advance(const Duration(days: 3));
    plan = await journey.currentPlan();
    expect(plan.step('q01.s02')!.resurfaced, isTrue);

    await journey.comeBackLater('q01.s02');
    plan = await journey.currentPlan();
    expect(plan.step('q01.s02')!.status, StepStatus.postponed);
  });

  test(
    '"I don\'t know" on a choice is recorded as the fact "unknown"',
    () async {
      await journey.saveAnswer('diag.s01', 'stage', const Answer.unknown());
      await journey.saveAnswer('diag.s01', 'hours', const Answer.unknown());
      await journey.saveAnswer(
        'diag.s01',
        'name',
        const Answer(AnswerType.text, 'Projet'),
      );
      await journey.complete('diag.s01');
      final facts = await FactsRepository(db).all();
      expect(facts['diag.idea_stage'], 'unknown');
    },
  );

  test(
    'advanced profile: the learning step is skipped, the deliverable asked',
    () async {
      await doDiagnostic(stage: 'existing_activity');
      final plan = await journey.currentPlan();
      expect(plan.next!.step.id, 'q01.s02');
      expect(plan.next!.fastTrack, isTrue);
      await journey.saveAnswer(
        'q01.s02',
        'problem',
        const Answer(AnswerType.text, 'x'),
      );
      expect(
        await journey.complete('q01.s02', fastTrack: true),
        isA<StepCompleted>(),
      );
      expect(
        (await journey.currentPlan()).step('q01.s02')!.status,
        StepStatus.fastTracked,
      );
    },
  );

  test('the plan stream follows changes', () async {
    final plans = journey.watchPlan();
    final first = await plans.first;
    expect(first.diagnosticDone, isFalse);
    await doDiagnostic();
    expect((await journey.watchPlan().first).diagnosticDone, isTrue);
  });
}
