import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:eripoo/app/startup/app_services.dart';
import 'package:eripoo/app/startup/local_data_eraser.dart';
import 'package:eripoo/core/logging/app_logger.dart';
import 'package:eripoo/features/account/application/account_linker.dart';
import 'package:eripoo/features/media/data/media_store.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/security/key_manager.dart';
import 'package:eripoo/sync/engine/sync_engine.dart';
import 'package:eripoo/sync/remote/sync_remote.dart';
import 'package:eripoo/sync/sync_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/memory_secure_store.dart';

const owner = '0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a';
const sessionEntry = 'eripoo.session'; // SecureSessionStorage

/// A phone with a real encrypted database file and its own auth session.
class Phone {
  Phone(this.server, this.dir, this.session)
    : file = File('${dir.path}/eripoo.sqlite');

  final FakeSyncServer server;
  final Directory dir;
  final String session;
  final File file;
  final store = MemorySecureKeyStore();
  final logs = MemoryLogSink();
  late AppServices services;

  Future<void> start() async {
    services = await AppServices.start(store, file: file);
    // What a sign-in leaves on the phone (opaque here).
    await store.write(sessionEntry, 'tokens-of-$session');
  }

  ProjectRepository get projects => ProjectRepository(services.database);

  SyncSession get syncSession => SyncSession(
    ownerId: owner,
    deviceId: services.keys.deviceId,
    recordKey: DataKeys(services.crypto, services.keys.dataKey).records,
    umkVersion: services.keys.dataKeyVersion,
  );

  SyncEngine engine({String? withSession}) => SyncEngine(
    db: services.database,
    remote: server.clientFor(owner, session: withSession ?? session),
    crypto: services.crypto,
    logger: AppLogger(sinks: [logs]),
  );

  SyncRunner runner() => SyncRunner(
    engine: engine(),
    eraseLocalData: () =>
        LocalDataEraser(store: store, databaseFile: file).eraseAll(
          reason: ErasureReason.deviceRevoked,
          openDatabase: services.database,
        ),
    logger: AppLogger(sinks: [logs]),
  );
}

void main() {
  late Directory dir;
  late FakeSyncServer server;

  // Two phones in one process: two databases on different files.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('eripoo_revoke');
    server = FakeSyncServer();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('13. revoked device: sync refused, local data erased, nothing '
      'resumes with the old credentials', () async {
    final a = Phone(server, Directory('${dir.path}/a')..createSync(), 'sA');
    await a.start();
    await AccountLinker(
      db: a.services.database,
      keyManager: a.services.keyManager,
      remote: server.clientFor(owner, session: 'sA'),
    ).link(ownerId: owner, localKeys: a.services.keys);
    await a.projects.create('Atelier de couture');

    // 1. A is synchronised.
    final first = await a.runner().run(a.syncSession);
    expect(first, isA<SyncRan>());
    expect((first as SyncRan).report.complete, isTrue);
    expect(server.recordsOf(owner), isNotEmpty);
    final oldDeviceId = a.services.keys.deviceId;

    // Unsynchronised work done after the last sync.
    await a.projects.create('Brouillon non envoyé');
    // An encrypted photo (fictitious bytes).
    final media = MediaStore(
      db: a.services.database,
      crypto: a.services.crypto,
      key: DataKeys(a.services.crypto, a.services.keys.dataKey).media,
      umkVersion: a.services.keys.dataKeyVersion,
      dir: a.services.mediaDirectory,
    );
    final photoId = await media.addPhoto(
      Uint8List.fromList([0xff, 0xd8, 0xff, 1, 2, 3]),
      mime: 'image/jpeg',
    );
    expect(media.fileOf(photoId).existsSync(), isTrue);

    // 2. A is revoked from another device.
    server.revoke(owner, oldDeviceId);
    final recordsBefore = Map.of(server.recordsOf(owner));

    // 3–4. A tries to sync: refused, nothing sent.
    final outcome = await a.runner().run(a.syncSession);
    expect(outcome, isA<DeviceRemoved>());
    expect(server.recordsOf(owner), recordsBefore);

    // 5. Policy: database, keys, device id and session are gone.
    for (final suffix in ['', '-wal', '-shm']) {
      expect(File('${a.file.path}$suffix').existsSync(), isFalse);
    }
    expect(a.store.values.keys, [LocalDataEraser.reasonEntry]);
    expect(a.services.mediaDirectory.existsSync(), isFalse);
    expect(
      a.logs.records.map((r) => r.event),
      contains('SyncRunLog.deviceRevokedLocalDataErased'),
    );

    // 6. After a restart: an empty app with a new device id, and the
    // reason is known so it can be explained.
    await a.start();
    addTearDown(a.services.database.close);
    expect(a.services.keys.deviceId, isNot(oldDeviceId));
    expect(await a.projects.watchActive().first, isEmpty);
    expect(
      await LocalDataEraser.lastReason(a.store),
      ErasureReason.deviceRevoked,
    );
    expect(await a.services.database.readValue(AccountLinker.ownerKey), isNull);

    // 7. The old credentials cannot resume anything, silently or not:
    // the old session is refused even with the new device id...
    await expectLater(
      a.engine(withSession: 'sA').runCycle(a.syncSession),
      throwsA(isA<DeviceRevoked>()),
    );
    expect(server.deviceStatus(owner, a.services.keys.deviceId), isNull);
    // ...and a new sign-in only gets the account back with the recovery
    // code (the data key is not on this device any more).
    final relink = await AccountLinker(
      db: a.services.database,
      keyManager: a.services.keyManager,
      remote: server.clientFor(owner, session: 'sA-new-sign-in'),
    ).link(ownerId: owner, localKeys: a.services.keys);
    expect(relink, isA<RecoveryNeeded>());
  });

  test(
    'other devices of the account keep working after a revocation',
    () async {
      final a = Phone(server, Directory('${dir.path}/a')..createSync(), 'sA');
      final b = Phone(server, Directory('${dir.path}/b')..createSync(), 'sB');
      await a.start();
      await AccountLinker(
        db: a.services.database,
        keyManager: a.services.keyManager,
        remote: server.clientFor(owner, session: 'sA'),
      ).link(ownerId: owner, localKeys: a.services.keys);
      await a.runner().run(a.syncSession);
      await b.start();
      addTearDown(b.services.database.close);

      server.revoke(owner, a.services.keys.deviceId);
      expect(await a.runner().run(a.syncSession), isA<DeviceRemoved>());

      // B registers and syncs normally with its own session.
      expect(await b.runner().run(b.syncSession), isA<SyncRan>());
      expect(server.deviceStatus(owner, b.services.keys.deviceId), 'active');
    },
  );

  test(
    'an invalid session asks to sign in again and keeps local data',
    () async {
      final a = Phone(server, Directory('${dir.path}/a')..createSync(), 'sA');
      await a.start();
      addTearDown(a.services.database.close);
      await a.projects.create('Gardé');
      final runner = SyncRunner(
        engine: SyncEngine(
          db: a.services.database,
          remote: _Unauthenticated(),
          crypto: a.services.crypto,
          logger: AppLogger(sinks: const []),
        ),
        eraseLocalData: () async => fail('must not erase'),
        logger: AppLogger(sinks: const []),
      );
      expect(await runner.run(a.syncSession), isA<SignInNeeded>());
      expect(await a.projects.watchActive().first, hasLength(1));
    },
  );
}

class _Unauthenticated implements SyncRemote {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(const NotAuthenticated());
}
