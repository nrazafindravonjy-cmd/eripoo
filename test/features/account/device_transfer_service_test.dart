// Adding a phone by double QR, between two simulated phones and the fake
// server: the key arrives, is checked against the account's data, the
// new phone's own photos stay readable, and every interruption of
// docs/SECURITY.md §6.7 leaves a state that a new attempt can finish.
// Fictitious data only.
import 'dart:io';
import 'dart:typed_data';

import 'package:eripoo/core/logging/app_logger.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/account/application/account_linker.dart';
import 'package:eripoo/features/account/application/device_transfer_service.dart';
import 'package:eripoo/features/media/data/media_store.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:eripoo/security/device_transfer.dart';
import 'package:eripoo/security/key_manager.dart';
import 'package:eripoo/sync/engine/sync_engine.dart';
import 'package:eripoo/sync/remote/sync_remote.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_sync_server.dart';
import '../../helpers/memory_secure_store.dart';
import '../../helpers/test_database.dart';

const owner = '0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a';
const otherOwner = '0192f2a0-7c1e-7b3a-9c2d-00000000beef';

/// One phone: its keystore, encrypted database, photos and keys. [restart]
/// reloads the keys as the app does at start-up.
class Phone {
  Phone(this.crypto, this.server, this.label)
    : store = MemorySecureKeyStore(),
      db = memoryDatabase(),
      mediaDir = Directory.systemTemp.createTempSync('eripoo_xfer');

  final CryptoService crypto;
  final FakeSyncServer server;
  final String label;
  final MemorySecureKeyStore store;
  final AppDatabase db;
  final Directory mediaDir;
  late KeyManager keyManager;
  late LocalKeys keys;
  DataKeys? _data;
  DataKeys? _previous;

  Future<void> start({bool databaseExists = false}) async {
    keyManager = KeyManager(crypto, store);
    keys = await keyManager.loadOrCreate(databaseExists: databaseExists);
    _data = DataKeys(crypto, keys.dataKey);
    final previous = await keyManager.previousDataKey();
    _previous = previous == null ? null : DataKeys(crypto, previous.key);
  }

  Future<void> restart() async {
    _data?.dispose();
    _previous?.dispose();
    await start(databaseExists: true);
  }

  FakeSyncRemote get remote =>
      server.clientFor(owner, session: 'session-${keys.deviceId}');

  DeviceTransferService transfers({SyncRemote? via}) => DeviceTransferService(
    db: db,
    crypto: crypto,
    keyManager: keyManager,
    remote: via ?? remote,
  );

  MediaStore get media => MediaStore(
    db: db,
    crypto: crypto,
    key: _data!.media,
    umkVersion: keys.dataKeyVersion,
    dir: mediaDir,
    previousKey: _previous?.media,
  );

  ProjectRepository get projects => ProjectRepository(db);

  Future<SyncReport> sync() =>
      SyncEngine(
        db: db,
        remote: remote,
        crypto: crypto,
        logger: AppLogger(sinks: [MemoryLogSink()]),
      ).runCycle(
        SyncSession(
          ownerId: owner,
          deviceId: keys.deviceId,
          recordKey: _data!.records,
          umkVersion: keys.dataKeyVersion,
        ),
      );

  Future<String?> linkedOwner() => db.readValue(AccountLinker.ownerKey);

  Future<void> close() async {
    _data?.dispose();
    _previous?.dispose();
    await db.close();
    mediaDir.deleteSync(recursive: true);
  }
}

final photo = Uint8List.fromList([0xff, 0xd8, 0xff, ...List.filled(40, 3)]);

void main() {
  late CryptoService crypto;
  late FakeSyncServer server;
  late Phone a; // old phone, linked, with synced data
  late Phone n; // new phone, signed in, not linked yet

  setUpAll(() async => crypto = await CryptoService.init());

  setUp(() async {
    server = FakeSyncServer();
    a = Phone(crypto, server, 'Téléphone');
    n = Phone(crypto, server, 'Tablette');
    await a.start();
    await n.start();
    await a.db.writeValue(AccountLinker.ownerKey, owner);
    await a.projects.create('Savon du quartier');
    expect((await a.sync()).complete, isTrue);
  });

  tearDown(() async {
    await a.close();
    await n.close();
  });

  /// The optical part: QR1 on N, code typed on A, QR2 on A, read by N.
  Future<ReceivedKey> exchange() async {
    final r = n.transfers().startReceiving(
      ownerId: owner,
      deviceId: n.keys.deviceId,
      label: n.label,
    );
    final qr2 = await a.transfers().sealForNewDevice(
      qr1: r.qr1,
      typedCode: r.code,
      ownerId: owner,
      keys: a.keys,
    );
    return r.open(qr2);
  }

  Future<void> adopt(ReceivedKey key, {SyncRemote? via}) => n
      .transfers(via: via)
      .adoptReceivedKey(
        key,
        ownerId: owner,
        deviceId: n.keys.deviceId,
        deviceLabel: n.label,
      );

  test('the new phone gets the account key, keeps its own photo, and both '
      'phones converge', () async {
    // Before the account: a photo and a project on the new phone.
    final photoId = await n.media.addPhoto(photo, mime: 'image/jpeg');
    await n.projects.create('Couture');
    final before = n.mediaDir.listSync().single as File;
    final sealedBefore = before.readAsBytesSync();

    await adopt(await exchange());
    expect(await n.linkedOwner(), owner);
    expect(server.deviceStatus(owner, n.keys.deviceId), 'active');

    // "Restart": the account key is loaded; the photo is still readable
    // (previous key) and is re-encrypted with the account key.
    await n.restart();
    expect(n.keys.dataKey.extractBytes(), a.keys.dataKey.extractBytes());
    expect(await n.media.read(photoId), photo);
    expect(await n.media.resealAll(), 0);
    expect(before.readAsBytesSync(), isNot(sealedBefore));
    await n.keyManager.forgetPreviousDataKey();
    await n.restart();
    expect(await n.media.read(photoId), photo); // current key only

    // Synchronisation in both directions with the shared key.
    expect((await n.sync()).complete, isTrue);
    expect((await a.sync()).complete, isTrue);
    final onA = (await a.projects.watchActive().first).map((p) => p.title);
    final onN = (await n.projects.watchActive().first).map((p) => p.title);
    expect(onA, unorderedEquals(['Savon du quartier', 'Couture']));
    expect(onN, unorderedEquals(onA));
  });

  group('§6.7 interruptions', () {
    test('before QR2 is read: nothing changes', () async {
      final r = n.transfers().startReceiving(
        ownerId: owner,
        deviceId: n.keys.deviceId,
        label: n.label,
      );
      r.dispose(); // cancelled, or the app left for more than 30 s
      expect(n.store.values.containsKey('eripoo.umk.previous'), isFalse);
      expect(await n.linkedOwner(), isNull);
      expect(server.deviceStatus(owner, n.keys.deviceId), isNull);
    });

    test('closed after the scan, before storing: start again with a new '
        'QR1; the old QR2 is useless', () async {
      final r = n.transfers().startReceiving(
        ownerId: owner,
        deviceId: n.keys.deviceId,
        label: n.label,
      );
      final qr2 = await a.transfers().sealForNewDevice(
        qr1: r.qr1,
        typedCode: r.code,
        ownerId: owner,
        keys: a.keys,
      );
      r.dispose(); // the app was closed: the one-time key is gone
      expect(() => r.open(qr2), throwsA(isA<TransferRefused>()));
      final other = n.transfers().startReceiving(
        ownerId: owner,
        deviceId: n.keys.deviceId,
        label: n.label,
      );
      expect(() => other.open(qr2), throwsA(isA<TransferRefused>()));
      expect(other.isAlive, isFalse); // a failed attempt also ends it

      await adopt(await exchange());
      expect(await n.linkedOwner(), owner);
    });

    test('network lost while finishing: nothing stored, retry with the '
        'key kept in memory', () async {
      final key = await exchange();
      server.offline = true;
      await expectLater(adopt(key), throwsA(isA<RemoteUnavailable>()));
      expect(await n.linkedOwner(), isNull);
      expect(n.store.values.containsKey('eripoo.umk.previous'), isFalse);

      server.offline = false;
      await adopt(key);
      expect(await n.linkedOwner(), owner);
    });

    test('registered but closed before storing: a new transfer finishes, '
        'the phone is counted once', () async {
      // The first attempt reached the server, then the app was killed.
      await n.remote.registerDevice(n.keys.deviceId, n.label);
      await adopt(await exchange());
      expect(await n.linkedOwner(), owner);
      // A + N only.
      final devices = [a.keys.deviceId, n.keys.deviceId];
      for (final d in devices) {
        expect(server.deviceStatus(owner, d), 'active');
      }
    });

    test('key stored, killed before the photos were re-encrypted: they are '
        'still readable and re-encrypted at the next start', () async {
      final photoId = await n.media.addPhoto(photo, mime: 'image/jpeg');
      await adopt(await exchange());
      // Killed here: restart without resealAll, twice.
      await n.restart();
      await n.restart();
      expect(await n.media.read(photoId), photo);
      expect(await n.media.resealAll(), 0);
      await n.keyManager.forgetPreviousDataKey();
      await n.restart();
      expect(await n.media.read(photoId), photo);
    });
  });

  group('refusals', () {
    test('a key that does not open the account data is not stored', () async {
      // Someone who saw QR1 seals another key to it (right tid).
      final r = n.transfers().startReceiving(
        ownerId: owner,
        deviceId: n.keys.deviceId,
        label: n.label,
      );
      final forged =
          TransferOffer.parse(
            r.qr1,
            publicKeyBytes: crypto.boxPublicKeyBytes,
          ).sealKey(
            crypto,
            ownerId: owner,
            typedCode: r.code,
            umk: crypto.generateKey(),
            umkVersion: 1,
            senderDeviceId: a.keys.deviceId,
          );
      final umkBefore = n.store.values['eripoo.umk'];
      await expectLater(
        adopt(r.open(forged)),
        throwsA(
          isA<TransferRefused>().having(
            (e) => e.failure,
            'failure',
            TransferFailure.keyDoesNotMatch,
          ),
        ),
      );
      expect(n.store.values['eripoo.umk'], umkBefore);
      expect(await n.linkedOwner(), isNull);
    });

    test('a key of another version is not stored', () async {
      final r = n.transfers().startReceiving(
        ownerId: owner,
        deviceId: n.keys.deviceId,
        label: n.label,
      );
      final qr2 =
          TransferOffer.parse(
            r.qr1,
            publicKeyBytes: crypto.boxPublicKeyBytes,
          ).sealKey(
            crypto,
            ownerId: owner,
            typedCode: r.code,
            umk: a.keys.dataKey,
            umkVersion: 2, // the account's data is under version 1
            senderDeviceId: a.keys.deviceId,
          );
      await expectLater(adopt(r.open(qr2)), throwsA(isA<TransferRefused>()));
      expect(await n.linkedOwner(), isNull);
    });

    test('an account with no data yet: the key is accepted', () async {
      final fresh = FakeSyncServer();
      final key = await exchange();
      await adopt(key, via: fresh.clientFor(owner));
      expect(await n.linkedOwner(), owner);
    });

    test('five phones already: refused, nothing stored', () async {
      for (var i = 0; i < 4; i++) {
        await server
            .clientFor(owner, session: 'other-$i')
            .registerDevice('00000000-0000-4000-8000-00000000000$i', 'Autre');
      }
      await expectLater(
        adopt(await exchange()),
        throwsA(isA<DeviceLimitReached>()),
      );
      expect(await n.linkedOwner(), isNull);
    });

    test('a phone holding another account data is refused', () async {
      await n.db.writeValue(AccountLinker.ownerKey, otherOwner);
      await expectLater(
        adopt(await exchange()),
        throwsA(isA<AccountMismatch>()),
      );
    });

    test('an old phone not linked to the account has nothing to give', () {
      final r = n.transfers().startReceiving(
        ownerId: owner,
        deviceId: n.keys.deviceId,
        label: n.label,
      );
      expect(
        n.transfers().sealForNewDevice(
          qr1: r.qr1,
          typedCode: r.code,
          ownerId: owner,
          keys: n.keys,
        ),
        throwsA(isA<NotLinkedToAccount>()),
      );
    });

    test('the old phone refuses a wrong code or another account', () async {
      final r = n.transfers().startReceiving(
        ownerId: otherOwner,
        deviceId: n.keys.deviceId,
        label: n.label,
      );
      await expectLater(
        a.transfers().sealForNewDevice(
          qr1: r.qr1,
          typedCode: r.code,
          ownerId: owner,
          keys: a.keys,
        ),
        throwsA(isA<TransferRefused>()),
      );
      final offer = a.transfers().readOffer(r.qr1);
      expect(offer.label, 'Tablette');
    });
  });
}
