// Leaving a phone and deleting the account, on two phones with the
// server double. Fictitious account only (example.com).
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:eripoo/app/startup/app_services.dart';
import 'package:eripoo/app/startup/local_data_eraser.dart';
import 'package:eripoo/features/account/application/account_lifecycle.dart';
import 'package:eripoo/sync/remote/sync_remote.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/fake_sync_server.dart';
import '../../helpers/memory_secure_store.dart';

const email = 'tiana@example.com';
const password = 'mot-de-passe-de-test';

void main() {
  late Directory dir;
  late FakeSyncServer server;
  late FakeAccounts accounts;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('eripoo_lifecycle');
    server = FakeSyncServer();
    accounts = FakeAccounts();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// A signed-in phone registered on the account.
  Future<(FakeBackend, AppServices, MemorySecureKeyStore, File)> phone(
    String name, {
    bool create = false,
  }) async {
    final store = MemorySecureKeyStore();
    final file = File('${dir.path}/$name.sqlite');
    final services = await AppServices.start(store, file: file);
    final backend = FakeBackend(server, accounts, phone: name);
    if (create) {
      await backend.auth.signUpWithEmail(email, password);
    } else {
      await backend.auth.signInWithEmail(email, password);
    }
    await backend.sync.registerDevice(services.keys.deviceId, name);
    return (backend, services, store, file);
  }

  AccountLifecycle lifecycle(
    FakeBackend backend,
    AppServices services,
    MemorySecureKeyStore store,
    File file,
  ) => AccountLifecycle(
    remote: backend.sync,
    media: backend.media,
    auth: backend.auth,
    eraseLocal: (reason) => LocalDataEraser(
      store: store,
      databaseFile: file,
    ).eraseAll(reason: reason, openDatabase: services.database),
  );

  test('sign out and erase: this phone leaves the account and keeps '
      'nothing; the other phone and the account are untouched', () async {
    final (a, aServices, aStore, aFile) = await phone('a', create: true);
    final (b, bServices, _, _) = await phone('b');
    addTearDown(bServices.database.close);
    final owner = a.userId!;

    await lifecycle(
      a,
      aServices,
      aStore,
      aFile,
    ).signOutAndErase(deviceId: aServices.keys.deviceId);
    expect(server.deviceStatus(owner, aServices.keys.deviceId), 'revoked');
    expect(server.deviceStatus(owner, bServices.keys.deviceId), 'active');
    expect(aFile.existsSync(), isFalse);
    expect(await LocalDataEraser.lastReason(aStore), ErasureReason.signedOut);
    expect(a.auth.currentUser, isNull);
    await b.sync.pull(bServices.keys.deviceId, 0);
  });

  test('offline, the phone is erased anyway (removed later from another '
      'phone)', () async {
    final (a, aServices, aStore, aFile) = await phone('a', create: true);
    server.offline = true;
    await lifecycle(
      a,
      aServices,
      aStore,
      aFile,
    ).signOutAndErase(deviceId: aServices.keys.deviceId);
    expect(aFile.existsSync(), isFalse);
    expect(await LocalDataEraser.lastReason(aStore), ErasureReason.signedOut);
  });

  test('delete the account: files, records, key copy and devices gone, '
      'this phone erased', () async {
    final (a, aServices, aStore, aFile) = await phone('a', create: true);
    final owner = a.userId!;
    await a.media.upload(
      '0192f2a0-7c1e-7b3a-9c2d-000000000001',
      Uint8List.fromList([1, 2, 3]),
    );
    await a.sync.push(aServices.keys.deviceId, [
      RemotePut(
        id: '0192f2a0-7c1e-7b3a-9c2d-000000000002',
        changeId: '0192f2a0-7c1e-7b3a-9c2d-000000000003',
        baseVersion: null,
        deleted: false,
        umkVersion: 1,
        payload: Uint8List.fromList([4, 5, 6]),
      ),
    ]);

    await lifecycle(a, aServices, aStore, aFile).deleteAccount();
    expect(server.mediaOf(owner), isEmpty);
    expect(server.recordsOf(owner), isEmpty);
    expect(server.deviceStatus(owner, aServices.keys.deviceId), isNull);
    expect(server.deletedAccounts, contains(owner));
    expect(aFile.existsSync(), isFalse);
    expect(
      await LocalDataEraser.lastReason(aStore),
      ErasureReason.accountDeleted,
    );
  });

  test(
    'offline: nothing is erased on the phone, it can be tried again',
    () async {
      final (a, aServices, aStore, aFile) = await phone('a', create: true);
      addTearDown(aServices.database.close);
      server.offline = true;
      await expectLater(
        lifecycle(a, aServices, aStore, aFile).deleteAccount(),
        throwsA(isA<RemoteUnavailable>()),
      );
      expect(aFile.existsSync(), isTrue);
      expect(await LocalDataEraser.lastReason(aStore), isNull);
    },
  );
}
