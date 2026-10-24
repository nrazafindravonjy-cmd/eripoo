// Answering aloud through the real step screen, with a fake microphone and
// speaker: recorded, encrypted, played, replaced, deleted. Fictitious
// bytes only.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:eripoo/app/app.dart';
import 'package:eripoo/app/di/core_providers.dart';
import 'package:eripoo/app/router/app_router.dart';
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/hypotheses/presentation/research_providers.dart';
import 'package:eripoo/features/media/data/media_store.dart';
import 'package:eripoo/features/quest/data/answer_repository.dart';
import 'package:eripoo/features/quest/domain/answer.dart';
import 'package:eripoo/features/settings/domain/app_settings.dart';
import 'package:eripoo/features/settings/presentation/app_settings_controller.dart';
import 'package:eripoo/features/voice/application/voice_notes.dart';
import 'package:eripoo/features/voice/presentation/voice_providers.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/activate.dart';
import '../../helpers/journey_overrides.dart';
import '../../helpers/memory_secure_store.dart';
import '../../helpers/test_database.dart';
import '../../helpers/test_host.dart';

class _FakeRecorder implements VoiceRecorder {
  bool allowed = true;
  int takes = 0;
  String? path;
  bool cancelled = false;

  @override
  Future<bool> hasPermission() async => allowed;

  @override
  Future<void> start(String path) async => this.path = path;

  @override
  Future<String?> stop() async {
    takes++;
    await File(path!).writeAsBytes(List.filled(800, takes));
    return path;
  }

  @override
  Future<void> cancel() async => cancelled = true;
}

class _FakePlayer implements VoicePlayer {
  final played = <Uint8List>[];
  final paths = <String>[];

  @override
  Future<void> play(File file) async {
    paths.add(file.path);
    played.add(await file.readAsBytes());
  }

  @override
  Future<void> stop() async {}
}

void main() {
  late CryptoService crypto;
  late AppDatabase db;
  late Directory tmp;
  late MediaStore media;
  late _FakeRecorder recorder;
  late _FakePlayer player;

  setUpAll(() async => crypto = await CryptoService.init());
  setUp(() {
    db = memoryDatabase();
    tmp = Directory.systemTemp.createTempSync('eripoo_ui_voice');
    media = MediaStore(
      db: db,
      crypto: crypto,
      key: crypto.generateKey(),
      umkVersion: 1,
      dir: Directory('${tmp.path}/media')..createSync(),
    );
    recorder = _FakeRecorder();
    player = _FakePlayer();
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Directory voiceDir() => Directory('${tmp.path}/voice');

  Future<void> launch(WidgetTester tester) async {
    setSurfaceSize(tester, phoneSize);
    final container = ProviderContainer(
      overrides: [
        secureKeyStoreProvider.overrideWithValue(MemorySecureKeyStore()),
        ...journeyOverrides(db: db),
        initialSettingsProvider.overrideWithValue(
          const AppSettings(language: AppLanguage.fr),
        ),
        mediaStoreProvider.overrideWithValue(media),
        voiceRecorderProvider.overrideWithValue(recorder),
        voicePlayerProvider.overrideWithValue(player),
        voiceTempDirProvider.overrideWith((ref) async => voiceDir()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const EripooApp()),
    );
    await tester.pumpAndSettle();
    unawaited(container.read(routerProvider).push(AppRoutes.step('q01.s02')));
    await tester.pumpAndSettle();
  }

  /// Lets real file, isolate and database work finish.
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(done(), isTrue);
  }

  /// Outside recording, where nothing ticks.
  Future<void> tapSettled(WidgetTester tester, String label) async {
    final finder = find.text(label).last;
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await activate(tester, finder);
    await tester.pumpAndSettle();
  }

  /// Same, for a condition read from the database.
  Future<void> waitFor(
    WidgetTester tester,
    Future<bool> Function() done,
  ) async {
    var ok = false;
    for (var i = 0; i < 100 && !ok; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      ok = (await tester.runAsync(done))!;
    }
    expect(ok, isTrue);
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final finder = find.text(label).last;
    await tester.ensureVisible(finder);
    // Not pumpAndSettle: the recording clock ticks every second.
    await tester.pump(const Duration(milliseconds: 500));
    await activate(tester, finder);
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<Answer?> saved() async =>
      (await AnswerRepository(db).forStep('q01.s02'))['problem'];

  Future<List<MediaRow>> mediaRows() => db.select(db.mediaItems).get();

  Finder textField() => find.ancestor(
    of: find.textContaining('Ta réponse'),
    matching: find.byType(TextField),
  );

  testWidgets('record, keep, listen, record again, delete', (tester) async {
    await launch(tester);
    expect(find.text('Répondre à l\'oral'), findsOneWidget);
    expect(find.textContaining('Fonctionne sans connexion'), findsOneWidget);
    expect(find.textContaining('pas de transcription'), findsOneWidget);

    // Something typed is replaced by a recording (and said so).
    await tester.enterText(textField(), 'Brouillon');
    await tester.pump();
    expect(
      find.text('Une réponse orale remplace ce que tu as écrit ici.'),
      findsOneWidget,
    );

    await tap(tester, 'Répondre à l\'oral');
    await settle(
      tester,
      () => find.textContaining('Enregistrement').evaluate().isNotEmpty,
    );
    expect(find.textContaining('0:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('0:02'), findsOneWidget);

    await tap(tester, 'Arrêter et garder');
    await settle(
      tester,
      () => find.text('Réponse orale enregistrée').evaluate().isNotEmpty,
    );
    // The written field gives way to the spoken answer.
    expect(textField(), findsNothing);
    final first = (await tester.runAsync(saved))!;
    expect(first.type, AnswerType.voice);
    final rows = (await tester.runAsync(mediaRows))!;
    expect(rows.single.kind, 'audio');
    expect(rows.single.id, first.value);
    // No plain recording left behind.
    expect(voiceDir().listSync().whereType<File>(), isEmpty);

    await tap(tester, 'Écouter');
    await settle(tester, () => player.played.isNotEmpty);
    expect(player.played.single, List.filled(800, 1));
    await settle(tester, () => !File(player.paths.single).existsSync());

    // A new recording replaces the first, which is deleted for good.
    await tap(tester, 'Enregistrer à nouveau');
    await settle(
      tester,
      () => find.text('Arrêter et garder').evaluate().isNotEmpty,
    );
    await tap(tester, 'Arrêter et garder');
    await settle(tester, () => recorder.takes == 2);
    String? secondId;
    await waitFor(tester, () async {
      secondId = (await saved())?.value as String?;
      return secondId != null && secondId != first.value;
    });
    await settle(
      tester,
      () => !media.fileOf(first.value! as String).existsSync(),
    );
    final after = (await tester.runAsync(mediaRows))!;
    expect(after.map((r) => r.id), [secondId]);

    // Deleting asks first, then the question is asked again in writing.
    await tap(tester, 'Supprimer et écrire plutôt');
    await tester.pumpAndSettle();
    expect(find.text('Supprimer cette réponse orale ?'), findsOneWidget);
    await tap(tester, 'Supprimer');
    await settle(tester, () => textField().evaluate().isNotEmpty);
    expect(await tester.runAsync(saved), isNull);
    await settle(tester, () => !media.fileOf(secondId!).existsSync());
    expect(await tester.runAsync(mediaRows), isEmpty);
  });

  testWidgets('cancelling keeps nothing; a refused microphone is explained', (
    tester,
  ) async {
    await launch(tester);
    await tap(tester, 'Répondre à l\'oral');
    await settle(tester, () => find.text('Annuler').evaluate().isNotEmpty);
    File(recorder.path!).writeAsBytesSync(const [1, 2, 3]);
    await tap(tester, 'Annuler');
    await settle(tester, () => recorder.cancelled);
    await settle(tester, () => !File(recorder.path!).existsSync());
    expect(await tester.runAsync(saved), isNull);
    expect(await tester.runAsync(mediaRows), isEmpty);

    recorder.allowed = false;
    await settle(
      tester,
      () => find.text('Répondre à l\'oral').evaluate().isNotEmpty,
    );
    await tap(tester, 'Répondre à l\'oral');
    await settle(
      tester,
      () =>
          find.textContaining('n\'a pas accès au micro').evaluate().isNotEmpty,
    );
  });

  testWidgets('the recap says the answer was spoken, not written', (
    tester,
  ) async {
    await launch(tester);
    await tap(tester, 'Répondre à l\'oral');
    await settle(
      tester,
      () => find.text('Arrêter et garder').evaluate().isNotEmpty,
    );
    await tap(tester, 'Arrêter et garder');
    await settle(
      tester,
      () => find.text('Réponse orale enregistrée').evaluate().isNotEmpty,
    );
    await tapSettled(tester, 'Suivant');
    await tester.enterText(textField(), 'Des voisins');
    await tester.pumpAndSettle();
    await tapSettled(tester, 'Suivant');
    await tapSettled(tester, 'Tous les jours');
    await tapSettled(tester, 'Suivant');
    await settle(
      tester,
      () => find
          .text('Réponse orale (pas écrite dans le projet)')
          .evaluate()
          .isNotEmpty,
    );
  });

  testWidgets('a recording stops by itself at 3 minutes and is kept', (
    tester,
  ) async {
    await launch(tester);
    await tap(tester, 'Répondre à l\'oral');
    await settle(
      tester,
      () => find.text('Arrêter et garder').evaluate().isNotEmpty,
    );
    await tester.pump(VoiceNotes.maxDuration);
    await settle(
      tester,
      () => find
          .text('3 minutes au plus : ta réponse a été gardée.')
          .evaluate()
          .isNotEmpty,
    );
    expect(find.text('Réponse orale enregistrée'), findsOneWidget);
    expect(recorder.takes, 1);
    expect((await tester.runAsync(saved))!.type, AnswerType.voice);
  });
}
