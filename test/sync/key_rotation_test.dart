// Rotation of the data key (docs/SECURITY.md §4.10, D17) between two
// phones with real encrypted databases and the server double: new key and
// code, everything sealed again (records and files), the old key and code
// retired, the other phone told and brought back with the new code.
// Fictitious data only.
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:eripoo/app/startup/app_services.dart';
import 'package:eripoo/app/startup/local_data_eraser.dart';
import 'package:eripoo/core/logging/app_logger.dart';
import 'package:eripoo/features/account/application/account_linker.dart';
import 'package:eripoo/features/account/application/key_rotation.dart';
import 'package:eripoo/features/media/application/media_sync.dart';
import 'package:eripoo/features/media/data/media_store.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/security/envelopes.dart';
import 'package:eripoo/security/key_manager.dart';
import 'package:eripoo/sync/engine/sync_engine.dart';
import 'package:eripoo/sync/remote/sync_remote.dart';
import 'package:eripoo/sync/sync_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/memory_secure_store.dart';

const owner = '0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a';

class Phone {
  Phone(this.server, this.dir, this.session)
    : file = File('${dir.path}/eripoo.sqlite');

  final FakeSyncServer server;
  final Directory dir;
  final String session;
  final File file;
  final store = MemorySecureKeyStore();
  late AppServices services;
  DateTime now = DateTime.utc(2026, 10, 9, 8);

  Future<void> start() async {
    services = await AppServices.start(store, file: file);
  }

  /// What the app does after a key change (bootstrap): close, start
  /// again, re-encrypt local files when a previous key is kept, and forget
  /// it unless a rotation still needs it for the server copies.
  Future<void> restart() async {
    await services.database.close();
    await start();
    if (services.previousDataKey == null) return;
    await media.resealAll();
    if (await services.database.readValue(KeyRotation.stageKey) == null) {
      await services.keyManager.forgetPreviousDataKey();
    }
  }

  FakeSyncRemote get remote => server.clientFor(owner, session: session);

  ProjectRepository get projects => ProjectRepository(services.database);

  DataKeys get _keys => DataKeys(services.crypto, services.keys.dataKey);
  DataKeys? get _previous => services.previousDataKey == null
      ? null
      : DataKeys(services.crypto, services.previousDataKey!);

  SyncSession get syncSession => SyncSession(
    ownerId: owner,
    deviceId: services.keys.deviceId,
    recordKey: _keys.records,
    umkVersion: services.keys.dataKeyVersion,
    previousRecordKey: _previous?.records,
  );

  MediaStore get media => MediaStore(
    db: services.database,
    crypto: services.crypto,
    key: _keys.media,
    umkVersion: services.keys.dataKeyVersion,
    dir: services.mediaDirectory,
    previousKey: _previous?.media,
  );

  MediaSync get mediaSync => MediaSync(
    db: services.database,
    store: media,
    remote: server.mediaFor(owner, session: session),
    ownerId: owner,
  );

  SyncEngine get engine => SyncEngine(
    db: services.database,
    remote: remote,
    crypto: services.crypto,
    logger: AppLogger(sinks: const []),
  );

  KeyRotation get rotation => KeyRotation(
    db: services.database,
    crypto: services.crypto,
    keyManager: services.keyManager,
    remote: remote,
    clock: () => now,
  );

  SyncRunner get runner => SyncRunner(
    engine: engine,
    eraseLocalData: () =>
        LocalDataEraser(store: store, databaseFile: file).eraseAll(
          reason: ErasureReason.deviceRevoked,
          openDatabase: services.database,
        ),
    logger: AppLogger(sinks: const []),
    settleKey: (serverVersion) => rotation.settle(
      serverVersion: serverVersion,
      localVersion: services.keys.dataKeyVersion,
    ),
  );

  AccountLinker get linker => AccountLinker(
    db: services.database,
    keyManager: services.keyManager,
    remote: remote,
  );

  /// What the sync cycle does after the records while a rotation runs.
  Future<bool> rekeyStep() => rotation.continueRekey(
    engine: engine,
    session: syncSession,
    media: mediaSync,
    mediaAllowed: true,
  );
}

void main() {
  late Directory dir;
  late FakeSyncServer server;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('eripoo_rotate');
    server = FakeSyncServer();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  final photo = Uint8List.fromList([0xff, 0xd8, 0xff, ...List.filled(64, 7)]);

  /// A synchronised, with a photo on the server; B opened with the code.
  Future<(Phone, Phone, String)> twoPhones() async {
    final a = Phone(server, Directory('${dir.path}/a')..createSync(), 'sA');
    final b = Phone(server, Directory('${dir.path}/b')..createSync(), 'sB');
    await a.start();
    final linked = await a.linker.link(
      ownerId: owner,
      localKeys: a.services.keys,
    ) as NewAccountLinked;
    await a.projects.create('Savon du quartier');
    final photoId = await a.media.addPhoto(photo, mime: 'image/jpeg');
    expect(
      (await a.runner.run(a.syncSession) as SyncRan).report.complete,
      true,
    );
    expect((await a.mediaSync.uploadPending()).uploaded, 1);

    await b.start();
    final need = await b.linker.link(
      ownerId: owner,
      localKeys: b.services.keys,
    ) as RecoveryNeeded;
    await b.linker.unlockWithRecoveryCode(
      ownerId: owner,
      wrap: need.wrap,
      typedCode: linked.recoveryCode,
    );
    await b.restart();
    expect(await b.runner.run(b.syncSession), isA<SyncRan>());
    expect(await b.projects.watchActive().first, hasLength(1));
    addTearDown(() async {
      await a.services.database.close();
      await b.services.database.close();
    });
    return (a, b, photoId);
  }

  test('rotation: new key and code, everything sealed again, the old key '
      'and code retired, the other phone brought back', () async {
    final (a, b, photoId) = await twoPhones();
    final oldCode = (await server.clientFor(owner).getRecoveryWrap())!;

    final newCode = a.rotation.newRecoveryCode();
    await a.rotation.rotate(
      ownerId: owner,
      keys: a.services.keys,
      code: newCode,
    );
    expect(server.keyVersionOf(owner), 2);
    expect(await a.rotation.inProgress(), isTrue);
    expect(await a.services.keyManager.pendingDataKey(), isNull);

    // The new code opens the new key; the old one opens nothing any more.
    final wrap = (await server.clientFor(owner).getRecoveryWrap())!;
    expect(wrap.umkVersion, 2);
    expect(wrap.wrapId, isNot(oldCode.wrapId));

    // A restarts with the new key and seals everything again.
    await a.restart();
    expect(a.services.keys.dataKeyVersion, 2);
    expect(a.services.previousDataKey, isNotNull);
    expect(await a.runner.run(a.syncSession), isA<SyncRan>());
    expect(await a.rekeyStep(), isTrue);
    expect(await a.rotation.inProgress(), isFalse);
    expect(await a.services.keyManager.previousDataKey(), isNull);
    for (final record in server.recordsOf(owner).values) {
      if (record.payload != null) expect(record.umkVersion, 2);
    }
    // The server copy of the photo: version 2, opened by the new key only.
    final sealed = server.mediaOf(owner)[photoId]!;
    expect(EnvelopeHeader.read(sealed).umkVersion, 2);
    await a.restart();
    expect(a.services.previousDataKey, isNull);
    expect(await a.media.read(photoId), photo);

    // B, still on the old key: told, nothing sent, nothing lost.
    await b.projects.create('Fait sur B pendant ce temps');
    final before = Map.of(server.recordsOf(owner));
    final outcome = await b.runner.run(b.syncSession);
    expect(outcome, isA<KeyOutdated>());
    expect((outcome as KeyOutdated).serverVersion, 2);
    expect(server.recordsOf(owner), before);
    expect(await b.projects.watchActive().first, hasLength(2));

    // The old code does not open the new key.
    await expectLater(
      b.linker.unlockWithRecoveryCode(
        ownerId: owner,
        wrap: wrap,
        typedCode: '${'1' * 35}0',
      ),
      throwsA(anyOf(isA<WrongRecoveryCode>(), isA<MalformedRecoveryCode>())),
    );

    // B gets the new key with the new code, and everything flows again.
    await b.linker.unlockWithRecoveryCode(
      ownerId: owner,
      wrap: wrap,
      typedCode: newCode,
    );
    await b.restart();
    expect(b.services.keys.dataKeyVersion, 2);
    final again = await b.runner.run(b.syncSession);
    expect((again as SyncRan).report.complete, isTrue);
    expect(await a.runner.run(a.syncSession), isA<SyncRan>());
    expect(await a.projects.watchActive().first, hasLength(2));
    // B reads the photo sealed again by A.
    expect(await b.mediaSync.fetch(photoId), isTrue);
    expect(await b.media.read(photoId), photo);
  });

  test('a phone still holding the old key cannot add data nor give the '
      'old key back as the recovery copy', () async {
    final (a, b, _) = await twoPhones();
    await a.rotation.rotate(
      ownerId: owner,
      keys: a.services.keys,
      code: a.rotation.newRecoveryCode(),
    );
    // Sealed with the old key: refused one by one.
    final results = await b.remote.push(b.services.keys.deviceId, [
      RemotePut(
        id: '0192f2a0-7c1e-7b3a-9c2d-000000000001',
        changeId: '0192f2a0-7c1e-7b3a-9c2d-000000000002',
        baseVersion: null,
        deleted: false,
        umkVersion: 1,
        payload: Uint8List.fromList([1, 2, 3]),
      ),
    ]);
    expect((results.single as PushRejected).reason, 'stale_key');
    final oldWrap = b.services.keyManager.createRecoveryWrap(
      keys: b.services.keys,
      ownerId: owner,
      code: b.services.keyManager.generateRecoveryCode(),
    );
    await expectLater(
      b.remote.setRecoveryWrap(oldWrap),
      throwsA(isA<KeyVersionMismatch>()),
    );
  });

  test('the server switched but the answer was lost: the next '
      'synchronisation finishes the switch', () async {
    final (a, _, _) = await twoPhones();
    server.loseNextRotationResponse = true;
    await expectLater(
      a.rotation.rotate(
        ownerId: owner,
        keys: a.services.keys,
        code: a.rotation.newRecoveryCode(),
      ),
      throwsA(isA<RemoteUnavailable>()),
    );
    expect(server.keyVersionOf(owner), 2);
    expect(a.services.keys.dataKeyVersion, 1);
    expect(await a.services.keyManager.pendingDataKey(), isNotNull);

    expect(await a.runner.run(a.syncSession), isA<KeyAdopted>());
    await a.restart();
    expect(a.services.keys.dataKeyVersion, 2);
    expect(await a.services.keyManager.pendingDataKey(), isNull);
    expect(await a.runner.run(a.syncSession), isA<SyncRan>());
    expect(await a.rekeyStep(), isTrue);
    for (final record in server.recordsOf(owner).values) {
      if (record.payload != null) expect(record.umkVersion, 2);
    }
  });

  test('the request never reached the server: the unused key is dropped '
      'later, the old code keeps working', () async {
    final (a, _, _) = await twoPhones();
    server.offline = true;
    await expectLater(
      a.rotation.rotate(
        ownerId: owner,
        keys: a.services.keys,
        code: a.rotation.newRecoveryCode(),
      ),
      throwsA(isA<RemoteUnavailable>()),
    );
    server.offline = false;
    expect(server.keyVersionOf(owner), 1);
    // Right after: kept, a request might still be on its way.
    expect(await a.runner.run(a.syncSession), isA<SyncRan>());
    expect(await a.services.keyManager.pendingDataKey(), isNotNull);
    // Later: dropped; nothing changed.
    a.now = a.now.add(const Duration(minutes: 11));
    expect(await a.runner.run(a.syncSession), isA<SyncRan>());
    expect(await a.services.keyManager.pendingDataKey(), isNull);
    expect(a.services.keys.dataKeyVersion, 1);
  });

  test('refused (sign-in too old, or rotated elsewhere first): nothing '
      'changes on this phone', () async {
    final (a, b, _) = await twoPhones();
    final remote = a.remote..requireReauthentication = true;
    final rotation = KeyRotation(
      db: a.services.database,
      crypto: a.services.crypto,
      keyManager: a.services.keyManager,
      remote: remote,
    );
    await expectLater(
      rotation.rotate(
        ownerId: owner,
        keys: a.services.keys,
        code: rotation.newRecoveryCode(),
      ),
      throwsA(isA<ReauthenticationRequired>()),
    );
    expect(await a.services.keyManager.pendingDataKey(), isNull);
    expect(await rotation.inProgress(), isFalse);

    await b.rotation.rotate(
      ownerId: owner,
      keys: b.services.keys,
      code: b.rotation.newRecoveryCode(),
    );
    await expectLater(
      a.rotation.rotate(
        ownerId: owner,
        keys: a.services.keys,
        code: a.rotation.newRecoveryCode(),
      ),
      throwsA(isA<KeyVersionMismatch>()),
    );
    expect(await a.services.keyManager.pendingDataKey(), isNull);
    expect(a.services.keys.dataKeyVersion, 1);
    expect(server.rotations, 1);
  });

  test('one rotation at a time', () async {
    final (a, _, _) = await twoPhones();
    await a.rotation.rotate(
      ownerId: owner,
      keys: a.services.keys,
      code: a.rotation.newRecoveryCode(),
    );
    await a.restart();
    await expectLater(
      a.rotation.rotate(
        ownerId: owner,
        keys: a.services.keys,
        code: a.rotation.newRecoveryCode(),
      ),
      throwsA(isA<RotationBusy>()),
    );
  });
}
