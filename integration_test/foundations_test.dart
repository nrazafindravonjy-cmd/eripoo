// Phase 2 foundations on a real Android system (emulator in CI, or a
// reference phone). Prints `MEASURE <name> <value>` lines, copied into
// docs/DEVELOPMENT_PLAN.md (Phase 2 validation).
//
//   flutter test integration_test/foundations_test.dart -d <device>
//
// Fictitious data only. Erases Eripoo's own local data on the device.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:eripoo/app/app.dart';
import 'package:eripoo/app/di/core_providers.dart';
import 'package:eripoo/app/startup/app_services.dart';
import 'package:eripoo/content/content_pack.dart';
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:eripoo/core/logging/app_logger.dart';
import 'package:eripoo/features/app_lock/data/app_lock_adapters.dart';
import 'package:eripoo/features/app_lock/domain/app_lock_service.dart';
import 'package:eripoo/features/app_lock/presentation/app_lock_controller.dart';
import 'package:eripoo/features/app_lock/presentation/lock_screen.dart';
import 'package:eripoo/features/devices/application/qr_codec.dart';
import 'package:eripoo/features/hypotheses/application/research_service.dart';
import 'package:eripoo/features/hypotheses/domain/research.dart';
import 'package:eripoo/features/media/data/media_store.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/features/quest/application/journey_service.dart';
import 'package:eripoo/features/quest/presentation/journey_providers.dart';
import 'package:eripoo/features/settings/data/settings_store.dart';
import 'package:eripoo/features/settings/presentation/app_settings_controller.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:eripoo/security/device_transfer.dart';
import 'package:eripoo/security/key_manager.dart';
import 'package:eripoo/security/secure_key_store.dart';
import 'package:eripoo/sync/engine/sync_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/fake_sync_server.dart';
import '../test/helpers/memory_secure_store.dart';

void measure(String name, Object value) => debugPrint('MEASURE $name $value');

int median(List<int> values) => (List.of(values)..sort())[values.length ~/ 2];

Future<void> eraseEverything(SecureKeyStore store) async {
  await store.deleteAll();
  final file = await AppServices.databaseFile();
  for (final suffix in ['', '-wal', '-shm']) {
    final f = File('${file.path}$suffix');
    if (f.existsSync()) f.deleteSync();
  }
}

/// Runs [work] while a 4 ms timer measures how late the UI isolate's event
/// loop runs: the worst delay is the longest freeze a user could see.
Future<(T, int)> withLoopLatency<T>(Future<T> Function() work) async {
  var worst = 0;
  var last = DateTime.now();
  final timer = Timer.periodic(const Duration(milliseconds: 4), (_) {
    final now = DateTime.now();
    final late = now.difference(last).inMilliseconds - 4;
    if (late > worst) worst = late;
    last = now;
  });
  try {
    final result = await work();
    // Work done synchronously blocks the timer itself: count the gap since
    // its last tick too, or a full freeze would read as 0 ms.
    final tail = DateTime.now().difference(last).inMilliseconds - 4;
    return (result, tail > worst ? tail : worst);
  } finally {
    timer.cancel();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final store = KeystoreSecureKeyStore();
  const owner = '0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a';

  setUpAll(() async {
    await eraseEverything(store);
    measure(
      'android_sdk',
      Platform.operatingSystemVersion.replaceAll(' ', '_'),
    );
    measure('cpu_count', Platform.numberOfProcessors);
  });
  tearDownAll(() => eraseEverything(store));

  testWidgets('storage, keys, restart, key errors, deleted data', (_) async {
    final watch = Stopwatch()..start();
    var services = await AppServices.start(store);
    measure('first_start_keys_and_db_ms', watch.elapsedMilliseconds);
    await services.database.writeValue('probe', 'gardé');
    final deviceId = services.keys.deviceId;
    await services.database.close();

    final opens = <int>[];
    for (var i = 0; i < 5; i++) {
      watch
        ..reset()
        ..start();
      services = await AppServices.start(store);
      opens.add(watch.elapsedMilliseconds);
      expect(await services.database.readValue('probe'), 'gardé');
      expect(services.keys.deviceId, deviceId);
      await services.database.close();
    }
    measure('restart_keys_and_db_open_median_ms', median(opens));
    measure('restart_keys_and_db_open_all_ms', opens.join(','));

    final file = await AppServices.databaseFile();
    final header = String.fromCharCodes(file.readAsBytesSync().take(15));
    expect(header, isNot('SQLite format 3'), reason: 'encrypted on disk');

    // Wrong database key: start fails, the file is untouched.
    final dbk = (await store.read('eripoo.dbk'))!;
    final other = MemorySecureKeyStore();
    await KeyManager(
      await CryptoService.init(),
      other,
    ).loadOrCreate(databaseExists: false);
    await store.write('eripoo.dbk', other.values['eripoo.dbk']!);
    final before = file.lengthSync();
    Object? error;
    try {
      await AppServices.start(store);
    } on Object catch (e) {
      error = e;
    }
    expect(error, isNotNull);
    measure('wrong_db_key_error', error.runtimeType);
    expect(file.lengthSync(), before);
    await store.write('eripoo.dbk', dbk);
    services = await AppServices.start(store);
    expect(await services.database.readValue('probe'), 'gardé');
    await services.database.close();

    // Keys gone, database still there: explicit failure, no silent reset.
    final umk = (await store.read('eripoo.umk'))!;
    await store.delete('eripoo.umk');
    await expectLater(AppServices.start(store), throwsA(isA<LocalKeysLost>()));
    await store.write('eripoo.umk', umk);

    // Local database deleted, keys kept: a new empty database opens.
    for (final suffix in ['', '-wal', '-shm']) {
      final f = File('${file.path}$suffix');
      if (f.existsSync()) f.deleteSync();
    }
    services = await AppServices.start(store);
    expect(await services.database.readValue('probe'), isNull);
    expect(services.keys.deviceId, deviceId);
    await services.database.close();

    // User reset: everything erased, next start is a first start.
    await AppServices.resetLocalData(store);
    services = await AppServices.start(store);
    expect(services.keys.deviceId, isNot(deviceId));
    await services.database.close();
  });

  testWidgets('Argon2id cost, memory and UI freeze', (_) async {
    final crypto = await CryptoService.init();
    final salt = crypto.randomBytes(16);
    final grid = [
      const KdfParams(opsLimit: 2, memLimit: 32 << 20),
      const KdfParams(opsLimit: 2, memLimit: 64 << 20),
      const KdfParams(opsLimit: 3, memLimit: 64 << 20),
      const KdfParams(opsLimit: 4, memLimit: 64 << 20),
    ];
    for (final p in grid) {
      final name = 'argon2id_${p.opsLimit}x${p.memLimit >> 20}MiB';
      final runs = <int>[];
      var worstFreeze = 0;
      final rssBefore = ProcessInfo.currentRss;
      for (var i = 0; i < 3; i++) {
        final watch = Stopwatch()..start();
        final (_, freeze) = await withLoopLatency(
          () => Isolate.run(() async {
            final c = await CryptoService.init();
            c
                .deriveKeyFromSecret(
                  '12345678901234567890123456789012345',
                  salt,
                  p,
                )
                .dispose();
          }),
        );
        runs.add(watch.elapsedMilliseconds);
        if (freeze > worstFreeze) worstFreeze = freeze;
      }
      measure('${name}_runs_ms', runs.join(','));
      measure('${name}_ui_worst_delay_ms', worstFreeze);
      measure(
        '${name}_rss_delta_mib',
        (ProcessInfo.currentRss - rssBefore) >> 20,
      );
    }
    measure('max_rss_mib_after_argon2', ProcessInfo.maxRss >> 20);

    // Same derivation on the UI isolate, to show why it must not be done
    // there (freeze = full duration).
    final (_, onUi) = await withLoopLatency(() async {
      crypto
          .deriveKeyFromSecret(
            '12345678901234567890123456789012345',
            salt,
            KdfParams.recoveryDefault,
          )
          .dispose();
    });
    measure('argon2id_3x64MiB_on_ui_isolate_freeze_ms', onUi);
  });

  testWidgets('recovery code: creation, unlock, repeated wrong attempts', (
    _,
  ) async {
    await eraseEverything(store);
    final services = await AppServices.start(store);
    final km = services.keyManager;
    final watch = Stopwatch()..start();
    final code = km.generateRecoveryCode();
    final wrap = await km.createRecoveryWrapInBackground(
      keys: services.keys,
      ownerId: owner,
      code: code,
    );
    measure('recovery_wrap_create_ms', watch.elapsedMilliseconds);
    watch
      ..reset()
      ..start();
    (await km.openRecoveryWrapInBackground(
      wrap: wrap,
      ownerId: owner,
      typedCode: code,
    )).dispose();
    measure('recovery_wrap_open_ms', watch.elapsedMilliseconds);

    // A wrong (but well-formed) code costs a full derivation every time.
    final wrong = km.generateRecoveryCode();
    final attempts = <int>[];
    for (var i = 0; i < 5; i++) {
      watch
        ..reset()
        ..start();
      await expectLater(
        km.openRecoveryWrapInBackground(
          wrap: wrap,
          ownerId: owner,
          typedCode: wrong,
        ),
        throwsA(isA<WrongRecoveryCode>()),
      );
      attempts.add(watch.elapsedMilliseconds);
    }
    measure('recovery_wrong_code_attempts_ms', attempts.join(','));
    await services.database.close();
  });

  testWidgets('sync: 1 000 items, offline, network cut, no loss', (_) async {
    await eraseEverything(store);
    final services = await AppServices.start(store);
    final server = FakeSyncServer();
    final projects = ProjectRepository(services.database);
    final watch = Stopwatch()..start();
    for (var i = 0; i < 1000; i++) {
      await projects.create('Projet $i');
    }
    measure('local_write_1000_ms', watch.elapsedMilliseconds);

    final key = DataKeys(services.crypto, services.keys.dataKey).records;
    final session = SyncSession(
      ownerId: owner,
      deviceId: services.keys.deviceId,
      recordKey: key,
      umkVersion: 1,
    );
    SyncEngine engine() => SyncEngine(
      db: services.database,
      remote: server.clientFor(owner, session: services.keys.deviceId),
      crypto: services.crypto,
      logger: AppLogger(sinks: const []),
    );

    server.offline = true;
    expect((await engine().runCycle(session)).complete, isFalse);
    expect(await projects.watchActive().first, hasLength(1000));
    server.offline = false;

    watch
      ..reset()
      ..start();
    server.failPushAfter(8);
    final (first, freeze) = await withLoopLatency(
      () => engine().runCycle(session),
    );
    expect(first.complete, isFalse);
    expect((await engine().runCycle(session)).complete, isTrue);
    measure('sync_push_1000_with_cut_ms', watch.elapsedMilliseconds);
    measure('sync_ui_worst_delay_ms', freeze);
    expect(server.recordsOf(owner), hasLength(1000));
    expect(server.headOf(owner), 1000);
    measure('max_rss_mib_after_sync', ProcessInfo.maxRss >> 20);
    key.dispose();
    await services.database.close();
  });

  testWidgets('app lock: PIN, wrong PIN, background, restart, biometrics', (
    tester,
  ) async {
    await eraseEverything(store);
    final services = await AppServices.start(store);
    final authenticator = LocalAuthDeviceAuthenticator();
    measure('biometrics_available', await authenticator.canUseBiometrics());
    measure('device_screen_lock', await authenticator.isDeviceSecured());
    final service = AppLockService(
      store: SecureAppLockStore(store),
      hasher: const Argon2PinHasher(),
      authenticator: authenticator,
    );
    final watch = Stopwatch()..start();
    await service.enable('2580');
    measure('pin_enable_ms', watch.elapsedMilliseconds);
    await service.setTimeout(Duration.zero);

    final pack = ContentPack.parse(await rootBundle.loadString(basePackAsset));

    Future<ProviderContainer> launch() async {
      final container = ProviderContainer(
        overrides: [
          secureKeyStoreProvider.overrideWithValue(store),
          appServicesProvider.overrideWithValue(services),
          appLockServiceProvider.overrideWithValue(service),
          contentPackProvider.overrideWithValue(pack),
        ],
      );
      container.read(appSettingsProvider.notifier).setLanguage(AppLanguage.fr);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const EripooApp(),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    Future<void> typePin(String pin) async {
      for (final digit in pin.split('')) {
        await tester.tap(
          find.descendant(
            of: find.byType(LockScreen),
            matching: find.text(digit),
          ),
        );
        await tester.pump();
      }
      final w = Stopwatch()..start();
      await tester.tap(find.bySemanticsLabel('Confirmer'));
      // The check runs Argon2id on a background isolate: real time passes
      // without any frame, so pumpAndSettle alone can return too early.
      // Wait (at most 10 s) until the screen is gone or shows a message.
      while (w.elapsed < const Duration(seconds: 10)) {
        await tester.pump(const Duration(milliseconds: 20));
        if (find.byType(LockScreen).evaluate().isEmpty ||
            find.text("Ce n'est pas le bon code.").evaluate().isNotEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle();
      measure('pin_check_ui_ms', w.elapsedMilliseconds);
    }

    var container = await launch();
    expect(find.byType(LockScreen), findsOneWidget);
    await typePin('1111');
    expect(find.text("Ce n'est pas le bon code."), findsOneWidget);
    await typePin('2580');
    expect(find.byType(LockScreen), findsNothing);

    final controller = container.read(appLockControllerProvider.notifier);
    controller.onBackgrounded(DateTime.now());
    await controller.onResumed(DateTime.now());
    await tester.pumpAndSettle();
    expect(find.byType(LockScreen), findsOneWidget, reason: 'relocked');
    await typePin('2580');
    expect(find.byType(LockScreen), findsNothing);

    // Restart: a new app instance with the same stored settings is locked.
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    container = await launch();
    expect(find.byType(LockScreen), findsOneWidget);
    await typePin('2580');
    expect(find.byType(LockScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await services.database.close();
  });

  testWidgets('journey offline: welcome, diagnostic, first step, restart', (
    tester,
  ) async {
    await eraseEverything(store);
    final previousHttp = HttpOverrides.current;
    HttpOverrides.global = _NoNetwork();
    addTearDown(() => HttpOverrides.global = previousHttp);

    var services = await AppServices.start(store);
    final watch = Stopwatch()..start();
    final pack = ContentPack.parse(await rootBundle.loadString(basePackAsset));
    measure('content_pack_parse_ms', watch.elapsedMilliseconds);
    final journey = JourneyService(pack: pack, db: services.database);
    watch
      ..reset()
      ..start();
    await journey.currentPlan();
    measure('journey_plan_ms', watch.elapsedMilliseconds);

    Future<ProviderContainer> launch() async {
      final settingsStore = SettingsStore(services.database);
      final container = ProviderContainer(
        overrides: [
          secureKeyStoreProvider.overrideWithValue(store),
          appServicesProvider.overrideWithValue(services),
          contentPackProvider.overrideWithValue(pack),
          settingsStoreProvider.overrideWithValue(settingsStore),
          initialSettingsProvider.overrideWithValue(await settingsStore.load()),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const EripooApp(),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    // The encrypted database answers on a background isolate: a screen
    // can update after pumpAndSettle returns. Wait (at most 10 s) for it.
    Future<void> waitFor(Finder finder) async {
      final w = Stopwatch()..start();
      while (finder.evaluate().isEmpty && w.elapsed.inSeconds < 10) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> tapText(String text) async {
      await waitFor(find.text(text));
      final finder = find.text(text).last;
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      final w = Stopwatch()..start();
      await tester.tap(finder);
      await tester.pumpAndSettle();
      if (text == "Terminer l'étape") {
        measure('step_finish_ui_ms', w.elapsedMilliseconds);
      }
    }

    var container = await launch();
    await tapText('Français');
    await tapText('Continuer'); // welcome
    await tapText('Passer'); // introduction
    await tapText('Commencer'); // home: start the diagnostic
    await tapText('Suivant');
    await tapText("J'ai une idée, encore floue");
    await tapText('Suivant');
    await tapText('2 à 5 heures');
    await tapText('Suivant');
    await tapText('Commerce');
    await tapText('Suivant');
    await tapText('Seul ou seule');
    await tapText("Terminer l'étape");
    await tapText('Commencer');
    await tapText('Un revenu en plus');
    await tapText('Suivant');
    await tester.enterText(find.byType(TextField), 'Projet fictif');
    // Close the keyboard, as a user would, before moving on.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tapText('Suivant');
    await tapText("Terminer l'étape");
    await waitFor(find.widgetWithText(AppBar, 'Projet fictif'));
    expect(find.widgetWithText(AppBar, 'Projet fictif'), findsOneWidget);
    await tapText('Commencer'); // first journey step
    for (var i = 0; i < 3; i++) {
      await tapText('Suivant');
    }
    await tapText("Terminer l'étape");
    await waitFor(find.text('Le problème que tu vois'));
    expect(find.text('Le problème que tu vois'), findsOneWidget);

    // Restart: the database is closed and reopened (keys from the
    // Keystore); the journey continues where it was.
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await services.database.close();
    watch
      ..reset()
      ..start();
    services = await AppServices.start(store);
    container = await launch();
    measure('journey_restart_to_home_ms', watch.elapsedMilliseconds);
    await waitFor(find.widgetWithText(AppBar, 'Projet fictif'));
    expect(find.widgetWithText(AppBar, 'Projet fictif'), findsOneWidget);
    await waitFor(find.text('Le problème que tu vois'));
    expect(find.text('Le problème que tu vois'), findsOneWidget);
    expect(find.text('Bienvenue sur Eripoo'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await services.database.close();
  });

  testWidgets('project research: hypothesis tested to its conclusion, '
      'encrypted photos (300 KB and 10 MiB)', (tester) async {
    await eraseEverything(store);
    final services = await AppServices.start(store);
    final keys = DataKeys(services.crypto, services.keys.dataKey);
    final media = MediaStore(
      db: services.database,
      crypto: services.crypto,
      key: keys.media,
      umkVersion: services.keys.dataKeyVersion,
      dir: services.mediaDirectory,
    );
    final research = ResearchService(services.database);
    const project = '0192f2a0-0000-7000-8000-0000000000bb';

    // Photos: a typical resized photo, then the 10 MiB cap.
    for (final (name, size) in [('300kb', 300 * 1024), ('10mib', 10 << 20)]) {
      final bytes = Uint8List(size);
      for (var i = 0; i < size; i += 4096) {
        bytes[i] = i & 0xff;
      }
      final w = Stopwatch()..start();
      final (id, freeze) = await withLoopLatency(
        () => media.addPhoto(bytes, mime: 'image/jpeg'),
      );
      measure('media_${name}_encrypt_write_ms', w.elapsedMilliseconds);
      measure('media_${name}_ui_worst_delay_ms', freeze);
      w
        ..reset()
        ..start();
      final back = await media.read(id);
      measure('media_${name}_read_decrypt_ms', w.elapsedMilliseconds);
      expect(back!.length, size);
      expect(media.fileOf(id).lengthSync(), greaterThan(size));
    }

    final w = Stopwatch()..start();
    final h = await research.createHypothesis(
      projectId: project,
      statement: 'Les vendeuses commanderaient du savon livré.',
    );
    final e = await research.planExperiment(
      projectId: project,
      method: ExperimentMethod.preSale,
      plan: 'Proposer à 10 vendeuses.',
      hypothesisIds: [h.id],
      successCriterion: '6 commandes sur 10.',
    );
    await research.startExperiment(e.id);
    final r = await research.recordResult(
      e.id,
      summary: '7 commandes',
      yes: 7,
      total: 10,
    );
    final photo = await media.addPhoto(
      Uint8List.fromList([0xff, 0xd8, 0xff, 1, 2, 3]),
      mime: 'image/jpeg',
    );
    await research.addEvidence(
      projectId: project,
      subject: EvidenceSubject.result,
      subjectId: r.id,
      kind: EvidenceKind.photo,
      mediaId: photo,
    );
    await research.conclude(
      h.id,
      outcome: HypothesisStatus.validated,
      statement: 'Elles commandent.',
      confidenceAfter: 4,
    );
    measure('research_full_cycle_ms', w.elapsedMilliseconds);
    expect(
      (await research.hypothesis(h.id))!.status,
      HypothesisStatus.validated,
    );

    keys.dispose();
    await services.database.close();
    // Local data erasure removes the media files too.
    await AppServices.resetLocalData(store);
    expect(services.mediaDirectory.existsSync(), isFalse);
  });

  testWidgets('double-QR transfer: codes and QR reading speed', (_) async {
    final crypto = await CryptoService.init();
    final w = Stopwatch()..start();
    final n = TransferRequest.start(
      crypto,
      ownerId: '0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a',
      deviceId: '11111111-2222-4333-8444-555555555555',
      label: 'Téléphone de test',
    );
    final umk = crypto.generateKey();
    final qr2 =
        TransferOffer.parse(
          n.qr1,
          publicKeyBytes: crypto.boxPublicKeyBytes,
        ).sealKey(
          crypto,
          ownerId: '0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a',
          typedCode: n.code,
          umk: umk,
          umkVersion: 1,
          senderDeviceId: '99999999-8888-4777-8666-555555555555',
        );
    expect(n.open(qr2).umk.extractBytes(), umk.extractBytes());
    measure('transfer_protocol_ms', w.elapsedMilliseconds);

    // A 640x480 grey frame with QR1 on it, as the scanner gets it from
    // the camera, decoded in pure Dart (one frame of the scan loop).
    final modules = QrCodec.encode(
      TransferRequest.start(
        crypto,
        ownerId: '0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a',
        deviceId: '11111111-2222-4333-8444-555555555555',
        label: 'Téléphone de test',
      ).qr1,
    );
    final frame = Uint8List(640 * 480)..fillRange(0, 640 * 480, 230);
    for (var r = 0; r < modules.length; r++) {
      for (var c = 0; c < modules.length; c++) {
        if (!modules[r][c]) continue;
        for (var y = 0; y < 6; y++) {
          for (var x = 0; x < 6; x++) {
            frame[(60 + r * 6 + y) * 640 + 160 + c * 6 + x] = 25;
          }
        }
      }
    }
    var worst = 0;
    for (var i = 0; i < 5; i++) {
      w
        ..reset()
        ..start();
      expect(QrCodec.decode(frame, width: 640, height: 480), isNotNull);
      if (w.elapsedMilliseconds > worst) worst = w.elapsedMilliseconds;
    }
    measure('qr_decode_640x480_worst_ms', worst);
  });
}

/// Fails the test if anything opens a network connection.
class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('network used during the offline journey');
}
