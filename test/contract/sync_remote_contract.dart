import 'dart:typed_data';

import 'package:eripoo/core/ids/ids.dart';
import 'package:eripoo/core/logging/app_logger.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:eripoo/security/envelopes.dart';
import 'package:eripoo/sync/engine/sync_engine.dart';
import 'package:eripoo/sync/remote/media_remote.dart';
import 'package:eripoo/sync/remote/sync_remote.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

/// One signed-in session of a test user.
class ContractSession {
  ContractSession(this.ownerId, this.remote, this.media, this.handle);
  final String ownerId;
  final SyncRemote remote;
  final MediaRemote media;
  final Object handle;
}

/// What the contract needs from a server: the in-memory double or a real
/// Supabase. Every user is new and fictitious.
abstract class ContractHarness {
  Future<ContractSession> newUser();

  /// A second sign-in of the same user (another phone).
  Future<ContractSession> signInAgain(ContractSession user);
  SyncRemote anonymous();
  MediaRemote anonymousMedia();

  /// Whether this session can still obtain new tokens (refresh).
  Future<bool> canRefresh(ContractSession session);
  Future<void> dispose();
}

Uint8List _bytes(int seed, [int length = 48]) =>
    Uint8List.fromList(List.generate(length, (i) => (i * 31 + seed) & 0xff));

RemotePut _put(
  String id, {
  int? base,
  String? changeId,
  bool deleted = false,
  Uint8List? payload,
  int seed = 1,
}) => RemotePut(
  id: id,
  changeId: changeId ?? Ids.random(),
  baseVersion: base,
  deleted: deleted,
  umkVersion: 1,
  payload: deleted ? null : (payload ?? _bytes(seed)),
);

/// The behaviour every [SyncRemote] must have (docs/OFFLINE_SYNC.md §4).
/// Run on the fake (always) and on Supabase (CI), so the fake used by the
/// client tests is checked against the real server.
void syncRemoteContract(Future<ContractHarness> Function() create) {
  late ContractHarness h;
  setUp(() async => h = await create());
  tearDown(() => h.dispose());

  Future<(ContractSession, String)> registered() async {
    final user = await h.newUser();
    final device = Ids.random();
    await user.remote.registerDevice(device, 'Téléphone de test');
    return (user, device);
  }

  test('push applies, pull returns the same bytes', () async {
    final (u, d) = await registered();
    final id = Ids.newId();
    final payload = _bytes(7, 300);
    final results = await u.remote.push(d, [_put(id, payload: payload)]);
    expect(results.single, isA<PushApplied>());
    final version = (results.single as PushApplied).version;
    expect(version, 1);

    final page = await u.remote.pull(d, 0);
    expect(page.head, 1);
    final record = page.records.single;
    expect(record.id, id);
    expect(record.version, 1);
    expect(record.deviceId, d);
    expect(record.deleted, isFalse);
    expect(record.payload, payload);
  });

  test('a replayed change is idempotent', () async {
    final (u, d) = await registered();
    final put = _put(Ids.newId());
    final first = await u.remote.push(d, [put]);
    final again = await u.remote.push(d, [put]);
    expect(
      (again.single as PushApplied).version,
      (first.single as PushApplied).version,
    );
    expect((await u.remote.pull(d, 0)).head, 1);
  });

  test(
    'stale base and creation over an existing record are conflicts',
    () async {
      final (u, d) = await registered();
      final id = Ids.newId();
      await u.remote.push(d, [_put(id, seed: 1)]);
      await u.remote.push(d, [_put(id, base: 1, seed: 2)]);

      final stale = await u.remote.push(d, [_put(id, base: 1, seed: 3)]);
      final conflict = stale.single as PushConflict;
      expect(conflict.current!.version, 2);
      expect(conflict.current!.payload, _bytes(2));

      final create = await u.remote.push(d, [_put(id, seed: 4)]);
      expect(create.single, isA<PushConflict>());
    },
  );

  test('deletion leaves a tombstone without payload', () async {
    final (u, d) = await registered();
    final id = Ids.newId();
    await u.remote.push(d, [_put(id)]);
    final del = await u.remote.push(d, [_put(id, base: 1, deleted: true)]);
    expect(del.single, isA<PushApplied>());
    final record = (await u.remote.pull(d, 1)).records.single;
    expect(record.deleted, isTrue);
    expect(record.payload, isNull);
  });

  test('versions are contiguous and pull pages honour the limit', () async {
    final (u, d) = await registered();
    await u.remote.push(d, [for (var i = 0; i < 5; i++) _put(Ids.newId())]);
    final page = await u.remote.pull(d, 0, limit: 2);
    expect(page.head, 5);
    expect(page.records.map((r) => r.version), [1, 2]);
    final rest = await u.remote.pull(d, 2, limit: 10);
    expect(rest.records.map((r) => r.version), [3, 4, 5]);
    expect((await u.remote.pull(d, 5)).records, isEmpty);
  });

  test('batches over 50 are rejected', () async {
    final (u, d) = await registered();
    await expectLater(
      u.remote.push(d, [for (var i = 0; i < 51; i++) _put(Ids.newId())]),
      throwsA(isA<RemoteRejected>()),
    );
  });

  test('an unregistered device is refused', () async {
    final user = await h.newUser();
    await expectLater(
      user.remote.pull(Ids.random(), 0),
      throwsA(isA<DeviceUnknown>()),
    );
  });

  test('accounts are isolated', () async {
    final (a, d) = await registered();
    await a.remote.push(d, [_put(Ids.newId())]);
    final b = await h.newUser();
    await expectLater(b.remote.pull(d, 0), throwsA(isA<DeviceUnknown>()));
    final dB = Ids.random();
    await b.remote.registerDevice(dB, 'B');
    expect((await b.remote.pull(dB, 0)).records, isEmpty);
    expect(await b.remote.getRecoveryWrap(), isNull);
  });

  test('without a session nothing is reachable', () async {
    final anon = h.anonymous();
    await expectLater(
      anon.registerDevice(Ids.random(), 'X'),
      throwsA(isA<NotAuthenticated>()),
    );
    await expectLater(
      anon.pull(Ids.random(), 0),
      throwsA(isA<NotAuthenticated>()),
    );
    await expectLater(anon.getRecoveryWrap(), throwsA(isA<NotAuthenticated>()));
  });

  test('at most 5 active devices', () async {
    final user = await h.newUser();
    for (var i = 0; i < 5; i++) {
      await user.remote.registerDevice(Ids.random(), 'Appareil $i');
    }
    await expectLater(
      user.remote.registerDevice(Ids.random(), 'Sixième'),
      throwsA(isA<DeviceLimitReached>()),
    );
  });

  test('recovery wrap: stored as given, weak parameters refused, fetches '
      'rate limited', () async {
    final user = await h.newUser();
    final crypto = await CryptoService.init();
    final wrap = RecoveryWrap(
      wrapId: Ids.random(),
      umkVersion: 1,
      salt: crypto.randomBytes(16),
      params: KdfParams.recoveryDefault,
      wrapped: _bytes(9, 73),
    );
    await user.remote.setRecoveryWrap(wrap);
    final back = (await user.remote.getRecoveryWrap())!;
    expect(back.wrapId, wrap.wrapId);
    expect(back.salt, wrap.salt);
    expect(back.wrapped, wrap.wrapped);
    expect(back.params.opsLimit, 3);
    expect(back.params.memLimit, 64 << 20);

    await expectLater(
      user.remote.setRecoveryWrap(
        RecoveryWrap(
          wrapId: Ids.random(),
          umkVersion: 1,
          salt: crypto.randomBytes(16),
          params: const KdfParams(opsLimit: 1, memLimit: 8 << 20),
          wrapped: _bytes(9, 73),
        ),
      ),
      throwsA(isA<RemoteRejected>()),
    );
    await expectLater(
      user.remote.setRecoveryWrap(
        RecoveryWrap(
          wrapId: Ids.random(),
          umkVersion: 1,
          salt: crypto.randomBytes(8),
          params: KdfParams.recoveryDefault,
          wrapped: _bytes(9, 73),
        ),
      ),
      throwsA(isA<RemoteRejected>()),
    );
    for (var i = 1; i < 5; i++) {
      await user.remote.getRecoveryWrap();
    }
    await expectLater(
      user.remote.getRecoveryWrap(),
      throwsA(isA<RateLimited>()),
    );
  });

  test('13. revocation: the revoked session is refused everywhere and can '
      'no longer refresh; other devices continue', () async {
    final a = await h.newUser();
    final dA = Ids.random();
    await a.remote.registerDevice(dA, 'Téléphone perdu');
    await a.remote.pull(dA, 0);
    final b = await h.signInAgain(a);
    final dB = Ids.random();
    await b.remote.registerDevice(dB, 'Nouveau téléphone');

    await b.remote.revokeDevice(dA);

    await expectLater(a.remote.pull(dA, 0), throwsA(isA<DeviceRevoked>()));
    await expectLater(
      a.remote.registerDevice(Ids.random(), 'Autre identifiant'),
      throwsA(isA<DeviceRevoked>()),
    );
    await expectLater(a.remote.pull(dB, 0), throwsA(isA<DeviceRevoked>()));
    await expectLater(
      a.remote.getRecoveryWrap(),
      throwsA(isA<DeviceRevoked>()),
    );
    expect(await h.canRefresh(a), isFalse, reason: 'session ended');
    expect(await h.canRefresh(b), isTrue);
    expect((await b.remote.pull(dB, 0)).head, 0);
  });

  test('my devices: names and states, never the session; the asking '
      'device is marked', () async {
    final a = await h.newUser();
    final dA = Ids.random();
    await a.remote.registerDevice(dA, 'Téléphone');
    final b = await h.signInAgain(a);
    final dB = Ids.random();
    await b.remote.registerDevice(dB, 'Tablette');
    final list = await b.remote.listDevices(currentDeviceId: dB);
    expect(
      list.map((d) => d.label),
      unorderedEquals(['Téléphone', 'Tablette']),
    );
    expect(list.singleWhere((d) => d.current).id, dB);
    expect(list.every((d) => !d.revoked), isTrue);

    await b.remote.revokeDevice(dA);
    final after = await b.remote.listDevices(currentDeviceId: dB);
    expect(after.first.id, dB, reason: 'active devices first');
    expect(after.singleWhere((d) => d.id == dA).revoked, isTrue);
    await expectLater(a.remote.listDevices(), throwsA(isA<DeviceRevoked>()));
    final other = await h.newUser();
    expect(await other.remote.listDevices(), isEmpty);
  });

  group('media files', () {
    test('upload, download the same bytes, idempotent, delete', () async {
      final u = await h.newUser();
      final id = Ids.newId();
      final sealed = _bytes(3, 5000);
      expect(await u.media.download(id), isNull);
      await u.media.upload(id, sealed);
      await u.media.upload(id, sealed); // lost response, retried
      expect(await u.media.download(id), sealed);
      await u.media.delete(id);
      expect(await u.media.download(id), isNull);
      await u.media.delete(id);
    });

    test('accounts are isolated; no session, no file', () async {
      final a = await h.newUser();
      final id = Ids.newId();
      await a.media.upload(id, _bytes(4));
      final b = await h.newUser();
      expect(await b.media.download(id), isNull);
      await b.media.delete(id); // cannot delete someone else's file
      expect(await a.media.download(id), _bytes(4));
      await expectLater(
        h.anonymousMedia().download(id),
        throwsA(isA<NotAuthenticated>()),
      );
    });

    test('files over the cap are refused', () async {
      final u = await h.newUser();
      await expectLater(
        u.media.upload(Ids.newId(), Uint8List(10 * 1024 * 1024 + 44)),
        throwsA(isA<RemoteRejected>()),
      );
    });

    test('a removed device\'s session can neither read nor write', () async {
      final a = await h.newUser();
      final dA = Ids.random();
      await a.remote.registerDevice(dA, 'Téléphone perdu');
      final id = Ids.newId();
      await a.media.upload(id, _bytes(5));
      final b = await h.signInAgain(a);
      final dB = Ids.random();
      await b.remote.registerDevice(dB, 'Nouveau téléphone');
      await b.remote.revokeDevice(dA);

      expect(await a.media.download(id), isNull);
      await expectLater(
        a.media.upload(Ids.newId(), _bytes(6)),
        throwsA(isA<RemoteRejected>()),
      );
      expect(await b.media.download(id), _bytes(5));
    });
  });

  test('two devices converge through the real engine', () async {
    final crypto = await CryptoService.init();
    final umk = crypto.generateKey();
    final a = await h.newUser();
    final b = await h.signInAgain(a);
    final dbA = memoryDatabase();
    final dbB = memoryDatabase();
    final key = crypto.deriveSubkey(
      umk,
      EnvelopeFormat.recordKeyId,
      EnvelopeFormat.recordKeyContext,
    );
    addTearDown(() async {
      await dbA.close();
      await dbB.close();
      key.dispose();
      umk.dispose();
    });
    SyncSession session(String device) => SyncSession(
      ownerId: a.ownerId,
      deviceId: device,
      recordKey: key,
      umkVersion: 1,
    );
    final devA = Ids.random();
    final devB = Ids.random();
    SyncEngine engine(AppDatabase dbX, SyncRemote remote) => SyncEngine(
      db: dbX,
      remote: remote,
      crypto: crypto,
      logger: AppLogger(sinks: const []),
    );

    final pA = ProjectRepository(dbA);
    final project = await pA.create('Épicerie');
    expect(
      (await engine(dbA, a.remote).runCycle(session(devA))).complete,
      isTrue,
    );
    expect(
      (await engine(dbB, b.remote).runCycle(session(devB))).complete,
      isTrue,
    );
    final pB = ProjectRepository(dbB);
    expect((await pB.get(project.id))!.title, 'Épicerie');

    // Concurrent edits: one kept, the other set aside, both converge.
    await pA.rename(project.id, 'Version A');
    await pB.rename(project.id, 'Version B');
    await engine(dbA, a.remote).runCycle(session(devA));
    await engine(dbB, b.remote).runCycle(session(devB));
    await engine(dbA, a.remote).runCycle(session(devA));
    final titleA = (await pA.get(project.id))!.title;
    expect((await pB.get(project.id))!.title, titleA);
    expect(
      (await dbA.select(dbA.conflictCopies).get()).length +
          (await dbB.select(dbB.conflictCopies).get()).length,
      greaterThan(0),
    );
  });
}
