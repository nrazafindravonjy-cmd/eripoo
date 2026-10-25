// Spoken answers below the screen: encrypted at once, the plain file
// erased, never copied into the project, deleted for good when replaced.
// Fictitious bytes only.
import 'dart:io';
import 'dart:typed_data';

import 'package:eripoo/content/content_pack.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/media/data/media_store.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/features/quest/application/journey_service.dart';
import 'package:eripoo/features/quest/data/answer_repository.dart';
import 'package:eripoo/features/quest/domain/answer.dart';
import 'package:eripoo/features/quest/domain/step_session.dart';
import 'package:eripoo/features/trash/application/trash_service.dart';
import 'package:eripoo/features/voice/application/voice_notes.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/journey_overrides.dart';
import '../../helpers/test_database.dart';

void main() {
  late CryptoService crypto;
  late AppDatabase db;
  late Directory tmp;
  late MediaStore media;
  late VoiceNotes notes;

  setUpAll(() async => crypto = await CryptoService.init());
  setUp(() {
    db = memoryDatabase();
    tmp = Directory.systemTemp.createTempSync('eripoo_voice');
    media = MediaStore(
      db: db,
      crypto: crypto,
      key: crypto.generateKey(),
      umkVersion: 1,
      dir: Directory('${tmp.path}/media')..createSync(),
    );
    notes = VoiceNotes(
      media: media,
      trash: TrashService(db, media: media),
      tempDir: Directory('${tmp.path}/voice'),
    );
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  final speech = Uint8List.fromList(List.generate(4000, (i) => i % 251));

  Future<String> recorded() async {
    final path = await notes.newTempPath();
    await File(path).writeAsBytes(speech);
    return path;
  }

  test('keep encrypts the recording and erases the plain file', () async {
    final path = await recorded();
    final id = await notes.keep(path);
    expect(File(path).existsSync(), isFalse);
    final row = await (db.select(
      db.mediaItems,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.kind, 'audio');
    expect(row.mime, 'audio/mp4');
    // On disk, only ciphertext.
    final stored = media.fileOf(id).readAsBytesSync();
    expect(stored, isNot(containsAllInOrder(speech.take(64))));
    expect(await media.read(id), speech);
  });

  test('an empty or failed recording leaves no plain file', () async {
    final path = await notes.newTempPath();
    await File(path).writeAsBytes(const []);
    await expectLater(notes.keep(path), throwsA(isA<UnsupportedMedia>()));
    expect(File(path).existsSync(), isFalse);
    expect(await db.select(db.mediaItems).get(), isEmpty);
  });

  test('only the app\'s own audio format is accepted', () async {
    await expectLater(
      media.addAudio(speech, mime: 'audio/mpeg'),
      throwsA(isA<UnsupportedMedia>()),
    );
    await expectLater(
      media.addPhoto(speech, mime: 'audio/mp4'),
      throwsA(isA<UnsupportedMedia>()),
    );
  });

  test('playing decrypts to a temporary file; the start-up purge erases '
      'whatever is left', () async {
    final id = await notes.keep(await recorded());
    final file = (await notes.openForPlaying(id))!;
    expect(file.readAsBytesSync(), speech);
    expect(file.path, startsWith('${tmp.path}/voice/'));
    await VoiceNotes.purgeTemp(Directory('${tmp.path}/voice'));
    expect(file.existsSync(), isFalse);
    expect(await notes.openForPlaying('missing'), isNull);
  });

  test('discard deletes the recording for good', () async {
    final id = await notes.keep(await recorded());
    await notes.discard(id);
    expect(media.fileOf(id).existsSync(), isFalse);
    expect(await media.read(id), isNull);
  });

  group('in the journey', () {
    late JourneyService journey;
    setUp(() => journey = JourneyService(pack: basePack(), db: db));

    test('open questions can be answered aloud, except the project name '
        'and choices', () {
      final pack = basePack();
      final diag = StepSession(step: pack.step('diag.s02')!);
      final q01 = StepSession(step: pack.step('q01.s02')!);
      QuestionBlock q(StepSession s, String id) =>
          s.step.block(id)! as QuestionBlock;
      expect(q01.canAnswerByVoice(q(q01, 'problem')), isTrue);
      expect(q01.canAnswerByVoice(q(q01, 'frequency')), isFalse);
      expect(diag.canAnswerByVoice(q(diag, 'name')), isFalse);
      expect(
        () => diag.answerVoice(q(diag, 'name'), 'm1'),
        throwsArgumentError,
      );
      expect(q01.answerVoice(q(q01, 'problem'), 'm1').isVoice, isTrue);
    });

    test('a spoken answer completes the step but is never copied into the '
        'project', () async {
      final project = await ProjectRepository(db).create('Projet test');
      final id = await notes.keep(await recorded());
      await journey.saveAnswer(
        'q01.s02',
        'problem',
        Answer(AnswerType.voice, id),
      );
      await journey.saveAnswer(
        'q01.s02',
        'who',
        const Answer(AnswerType.text, 'Des voisins'),
      );
      await journey.saveAnswer(
        'q01.s02',
        'frequency',
        const Answer(AnswerType.choice, 'daily'),
      );
      for (final id in ['causes', 'effects']) {
        await journey.saveAnswer(
          'q01.s02',
          id,
          const Answer(AnswerType.text, 'Loin'),
        );
      }
      expect(await journey.complete('q01.s02'), isA<StepCompleted>());
      final answers = await journey.answersOf('q01.s02');
      expect(answers['problem']!.type, AnswerType.voice);
      expect(answers['problem']!.value, id);
      final sections = await ProjectRepository(db).sections(project.id);
      expect(sections['problem']!.fields['statement'], isNull);
      expect(sections['customers']!.fields['first_guess'], 'Des voisins');
    });

    test('a deleted answer is asked again; saving it again brings it '
        'back', () async {
      final answers = AnswerRepository(db);
      await journey.saveAnswer(
        'q01.s02',
        'problem',
        const Answer(AnswerType.voice, 'm1'),
      );
      await journey.deleteAnswer('q01.s02', 'problem');
      expect(await answers.forStep('q01.s02'), isEmpty);
      await journey.saveAnswer(
        'q01.s02',
        'problem',
        const Answer(AnswerType.text, 'Écrit'),
      );
      expect((await answers.forStep('q01.s02'))['problem']!.value, 'Écrit');
    });
  });
}
