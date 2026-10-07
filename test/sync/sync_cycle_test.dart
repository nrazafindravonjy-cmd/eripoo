// One automatic attempt: records first, then photos on Wi-Fi only (unless
// the user allowed mobile data); what the scheduler is told in each case.
// Fictitious data only.
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:eripoo/app/sync/sync_setup.dart';
import 'package:eripoo/core/ids/ids.dart';
import 'package:eripoo/core/logging/app_logger.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/media/application/media_sync.dart';
import 'package:eripoo/features/media/data/media_store.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:eripoo/security/key_manager.dart';
import 'package:eripoo/sync/engine/sync_engine.dart';
import 'package:eripoo/sync/sync_cycle.dart';
import 'package:eripoo/sync/sync_runner.dart';
import 'package:eripoo/sync/sync_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/media/media_store_test.dart' as plain;
import '../helpers/fake_sync_server.dart';
import '../helpers/test_database.dart';

const owner = '0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a';

void main() {
  late CryptoService crypto;
  late FakeSyncServer server;
  late AppDatabase db;
  late Directory dir;
  late DataKeys keys;
  late MediaStore store;
  late String deviceId;
  late NetworkKind network;
  var erased = 0;

  setUpAll(() async => crypto = await CryptoService.init());
  setUp(() {
    server = FakeSyncServer();
    db = memoryDatabase();
    dir = Directory.systemTemp.createTempSync('eripoo_cycle');
    keys = DataKeys(crypto, crypto.generateKey());
    store = MediaStore(
      db: db,
      crypto: crypto,
      key: keys.media,
      umkVersion: 1,
      dir: dir,
    );
    deviceId = Ids.random();
    network = NetworkKind.unmetered;
    erased = 0;
  });
  tearDown(() async {
    keys.dispose();
    await db.close();
    dir.deleteSync(recursive: true);
  });

  SyncCycle cycle() => SyncCycle(
    db: db,
    runner: SyncRunner(
      engine: SyncEngine(
        db: db,
        remote: server.clientFor(owner, session: deviceId),
        crypto: crypto,
        logger: AppLogger(sinks: const []),
      ),
      eraseLocalData: () async => erased++,
      logger: AppLogger(sinks: const []),
    ),
    session: () => SyncSession(
      ownerId: owner,
      deviceId: deviceId,
      recordKey: keys.records,
      umkVersion: 1,
    ),
    media: MediaSync(
      db: db,
      store: store,
      remote: server.mediaFor(owner, session: deviceId),
      ownerId: owner,
    ),
    network: () async => network,
  );

  Future<void> work() async {
    await ProjectRepository(db).create('Savon du quartier');
    await store.addPhoto(plain.fakePhoto(), mime: 'image/jpeg');
  }

  test('Wi-Fi: records then photos, all saved', () async {
    await work();
    final c = cycle();
    expect(await c(), SyncAttempt.complete);
    expect(c.lastReport!.complete, isTrue);
    expect(server.mediaOf(owner), hasLength(1));
  });

  test('mobile data: records saved, photos wait for Wi-Fi without counting '
      'as a failure', () async {
    await work();
    network = NetworkKind.metered;
    expect(await cycle()(), SyncAttempt.complete);
    expect(server.recordsOf(owner), isNotEmpty);
    expect(server.mediaOf(owner), isEmpty);

    await db.writeValue(SyncCycle.mediaOnMobileDataKey, '1'); // allowed
    expect(await cycle()(), SyncAttempt.complete);
    expect(server.mediaOf(owner), hasLength(1));
  });

  test('no network: no call at all, retried later', () async {
    await work();
    network = NetworkKind.none;
    final calls = server.pushCalls;
    expect(await cycle()(), SyncAttempt.incomplete);
    expect(server.pushCalls, calls);
  });

  test('server unreachable: retried later, nothing lost', () async {
    await work();
    server.offline = true;
    expect(await cycle()(), SyncAttempt.incomplete);
    server.offline = false;
    expect(await cycle()(), SyncAttempt.complete);
    expect(server.mediaOf(owner), hasLength(1));
  });

  test('removed phone: erased, everything stops', () async {
    await work();
    expect(await cycle()(), SyncAttempt.complete);
    server.revoke(owner, deviceId);
    expect(await cycle()(), SyncAttempt.removed);
    expect(erased, 1);
  });

  test('network kinds', () {
    expect(networkKindOf([]), NetworkKind.none);
    expect(networkKindOf([ConnectivityResult.none]), NetworkKind.none);
    expect(networkKindOf([ConnectivityResult.wifi]), NetworkKind.unmetered);
    expect(
      networkKindOf([ConnectivityResult.mobile, ConnectivityResult.wifi]),
      NetworkKind.unmetered,
    );
    expect(networkKindOf([ConnectivityResult.mobile]), NetworkKind.metered);
    expect(networkKindOf([ConnectivityResult.vpn]), NetworkKind.metered);
  });
}
