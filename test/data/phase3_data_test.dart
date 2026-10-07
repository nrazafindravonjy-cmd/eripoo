import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/data/local/encrypted_database.dart';
import 'package:eripoo/features/missions/data/mission_repository.dart';
import 'package:eripoo/features/missions/domain/mission_state.dart';
import 'package:eripoo/features/quest/data/answer_repository.dart';
import 'package:eripoo/features/quest/data/progress_repository.dart';
import 'package:eripoo/features/quest/domain/answer.dart';
import 'package:eripoo/features/quest/domain/step_progress.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

Future<int> pendingOf(AppDatabase db, String type) async =>
    (await (db.select(
              db.syncMetaEntries,
            )..where((t) => t.entityType.equals(type) & t.changeId.isNotNull()))
            .get())
        .length;

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  test(
    'answers: one per block, every type round-trips, marked for sync',
    () async {
      final answers = AnswerRepository(db);
      Future<void> save(String block, Answer a) => answers.save(
        questId: 'q01',
        stepId: 'q01.s02',
        blockId: block,
        answer: a,
      );
      await save('text', const Answer(AnswerType.text, 'Le pain manque'));
      await save('choice', const Answer(AnswerType.choice, 'vague_idea'));
      await save('multi', const Answer(AnswerType.multiChoice, ['a', 'b']));
      await save('number', const Answer(AnswerType.number, 3.5));
      await save('money', const Answer(AnswerType.money, 15000));
      await save('dunno', const Answer.unknown(helpUsed: 2));
      await save('text', const Answer(AnswerType.text, 'Le riz manque'));

      final got = await answers.forStep('q01.s02');
      expect(got.length, 6);
      expect(got['text']!.value, 'Le riz manque');
      expect(got['multi']!.value, ['a', 'b']);
      expect(got['money']!.value, 15000);
      expect(got['dunno']!.isUnknown, isTrue);
      expect(got['dunno']!.helpUsed, 2);
      expect(await answers.unknownCountByQuest(), {'q01': 1});
      expect(await pendingOf(db, 'answer'), 6);
    },
  );

  test('missions follow their life cycle', () async {
    final missions = MissionRepository(db);
    await missions.move('m.observe', MissionStatus.accepted);
    expect((await missions.get('m.observe'))!.acceptedAt, isNotNull);
    await expectLater(
      missions.move('m.observe', MissionStatus.completed),
      throwsA(isA<InvalidMissionTransition>()),
    );
    await missions.move(
      'm.observe',
      MissionStatus.submitted,
      reflection: 'J’ai vu des files au taxi-be',
    );
    await missions.move('m.observe', MissionStatus.completed);
    final done = (await missions.get('m.observe'))!;
    expect(done.status, MissionStatus.completed);
    expect(done.reflection, 'J’ai vu des files au taxi-be');
    await expectLater(
      missions.move('m.observe', MissionStatus.abandoned),
      throwsA(isA<InvalidMissionTransition>()),
    );
    expect(await pendingOf(db, 'mission_instance'), 1);
  });

  test('deferred steps keep their return date', () async {
    final progress = ProgressRepository(db);
    final until = DateTime.utc(2026, 10, 9);
    await progress.setStatus(
      'q01',
      'q01.s02',
      StepStatus.deferred,
      deferredUntil: until,
    );
    expect((await progress.all())['q01.s02']!.deferredUntil, until);
    await progress.setStatus('q01', 'q01.s02', StepStatus.inProgress);
    expect((await progress.all())['q01.s02']!.deferredUntil, isNull);
  });

  test('a schema v1 database migrates to the current one without losing '
      'data', () async {
    final dir = Directory.systemTemp.createTempSync('eripoo_migr');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/db.sqlite');
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    AppDatabase open() => AppDatabase(
      NativeDatabase(file, setup: (d) => applyDatabaseKey(d, key)),
    );

    // Build a v1 database: the v2 schema minus the Phase 3 additions.
    final v2 = open();
    await ProgressRepository(v2)
        .setStatus('q01', 'q01.s01', StepStatus.completed);
    await v2.customStatement('drop table answers');
    await v2.customStatement('drop table mission_instances');
    await v2.customStatement(
      'alter table step_progress_entries drop column deferred_until',
    );
    await v2.customStatement('pragma user_version = 1');
    await v2.close();

    final migrated = open();
    addTearDown(migrated.close);
    final kept = await ProgressRepository(migrated).get('q01.s01');
    expect(kept!.status, StepStatus.completed);
    await AnswerRepository(migrated).save(
      questId: 'q01',
      stepId: 'q01.s01',
      blockId: 'b',
      answer: const Answer(AnswerType.text, 'ok'),
    );
    await MissionRepository(migrated).move('m.x', MissionStatus.accepted);
    final version = await migrated
        .customSelect('pragma user_version')
        .getSingle();
    expect(version.data.values.single, migrated.schemaVersion);
  });
}
