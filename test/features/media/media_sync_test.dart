// Photos between two phones of the same account, through the fake server:
// sent once, sealed for the account (never plain, never the local file as
// is), fetched and checked on the other phone; network cuts, refusals and
// large files handled. Fictitious bytes only.
import 'dart:io';
import 'dart:typed_data';

import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/hypotheses/application/research_service.dart';
import 'package:eripoo/features/hypotheses/domain/hypothesis_states.dart';
import 'package:eripoo/features/media/application/media_sync.dart';
import 'package:eripoo/features/media/data/media_store.dart';
import 'package:eripoo/features/trash/application/trash_service.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:eripoo/security/key_manager.dart';
import 'package:eripoo/sync/engine/entity_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../helpers/fake_sync_server.dart';
import '../../helpers/test_database.dart';
import 'media_store_test.dart' as plain show contains, fakePhoto;

const owner = '0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a';

class Phone {
  Phone(CryptoService crypto, SecureKey umk, this.server, this.session)
    : db = memoryDatabase(),
      dir = Directory.systemTemp.createTempSync('eripoo_msync'),
      keys = DataKeys(crypto, umk) {
    store = MediaStore(
      db: db,
      crypto: crypto,
      key: keys.media,
      umkVersion: 1,
      dir: dir,
      clock: clock.call,
    );
  }

  final FakeSyncServer server;
  final String session;
  final AppDatabase db;
  final Directory dir;
  final DataKeys keys;
  final clock = TestClock();
  late final MediaStore store;

  MediaSync get media => MediaSync(
    db: db,
    store: store,
    remote: server.mediaFor(owner, session: session),
    ownerId: owner,
    clock: clock.call,
  );

  Future<void> close() async {
    keys.dispose();
    await db.close();
    dir.deleteSync(recursive: true);
  }
}

void main() {
  late CryptoService crypto;
  late SecureKey umk;
  late FakeSyncServer server;
  late Phone a;
  late Phone b;

  setUpAll(() async => crypto = await CryptoService.init());
  setUp(() {
    umk = crypto.generateKey();
    server = FakeSyncServer();
    a = Phone(crypto, umk, server, 'session-a');
    b = Phone(crypto, umk, server, 'session-b');
  });
  tearDown(() async {
    await a.close();
    await b.close();
    umk.dispose();
  });

  /// The metadata row reaches B (normally through the records' sync).
  Future<void> metadataToB(String id) async {
    final row = await EntityRegistry(a.db).read('media', id);
    await EntityRegistry(b.db).write('media', row!);
  }

  test('a photo is sent once, sealed for the account, and opens on the '
      'other phone', () async {
    final photo = plain.fakePhoto();
    final id = await a.store.addPhoto(photo, mime: 'image/jpeg');
    expect(await a.media.waitingCount(), 1);

    final report = await a.media.uploadPending();
    expect(report.uploaded, 1);
    expect(report.waiting, 0);
    final onServer = server.mediaOf(owner)[id]!;
    expect(plain.contains(onServer, 'PHOTO-EN-CLAIR'.codeUnits), isFalse);
    expect(
      onServer,
      isNot(a.store.fileOf(id).readAsBytesSync()),
      reason: 'sealed again for the account, not the local file',
    );
    expect((await a.media.uploadPending()).uploaded, 0);
    expect(server.mediaUploads, 1);

    await metadataToB(id);
    expect(await b.store.read(id), isNull, reason: 'not fetched yet');
    expect(await b.media.fetch(id), isTrue);
    expect(await b.store.read(id), photo);
    expect(await b.media.fetch(id), isTrue); // already there, no download
  });

  test('offline: the files wait, then go when the network is back', () async {
    final ids = [
      for (var i = 0; i < 3; i++)
        await a.store.addPhoto(plain.fakePhoto(100 + i), mime: 'image/jpeg'),
    ];
    server.offline = true;
    final cut = await a.media.uploadPending();
    expect(cut.uploaded, 0);
    expect(cut.waiting, 3);
    server.offline = false;
    expect((await a.media.uploadPending()).uploaded, 3);
    expect(server.mediaOf(owner).keys, unorderedEquals(ids));
  });

  test(
    'a refused file stays on the phone and is retried an hour later',
    () async {
      await a.store.addPhoto(plain.fakePhoto(), mime: 'image/jpeg');
      // The session of a removed device: the server refuses its uploads.
      await server.clientFor(owner, session: 'gone').registerDevice('d', 'X');
      server.revoke(owner, 'd');
      final refusing = MediaSync(
        db: a.db,
        store: a.store,
        remote: server.mediaFor(owner, session: 'gone'),
        ownerId: owner,
        clock: a.clock.call,
      );
      final first = await refusing.uploadPending();
      expect(first.refused, 1);
      expect(first.waiting, 1);
      expect((await a.media.uploadPending()).uploaded, 0, reason: 'waits 1 h');
      a.clock.advance(const Duration(minutes: 61));
      expect((await a.media.uploadPending()).uploaded, 1);
    },
  );

  test(
    'a photo in the trash waits; deleted forever, it is never sent',
    () async {
      final id = await a.store.addPhoto(plain.fakePhoto(), mime: 'image/jpeg');
      final evidence = await ResearchService(a.db).addEvidence(
        projectId: 'p',
        subject: EvidenceSubject.observation,
        subjectId: 'o',
        kind: EvidenceKind.photo,
        mediaId: id,
      );
      final trash = TrashService(a.db, media: a.store);
      await trash.moveToTrash(TrashKind.evidence, evidence.id);
      var report = await a.media.uploadPending();
      expect(report.uploaded, 0);
      expect(report.waiting, 0);

      await trash.restore(TrashKind.evidence, evidence.id);
      expect(await a.media.waitingCount(), 1, reason: 'restored: sent again');

      await trash.moveToTrash(TrashKind.evidence, evidence.id);
      await trash.purge(TrashKind.evidence, evidence.id);
      report = await a.media.uploadPending();
      expect(report.uploaded, 0);
      expect(server.mediaOf(owner), isEmpty);
      expect(a.store.hasFile(id), isFalse);
    },
  );

  test('not on the server yet; a swapped or damaged file is refused', () async {
    final id = await a.store.addPhoto(plain.fakePhoto(), mime: 'image/jpeg');
    await metadataToB(id);
    expect(await b.media.fetch(id), isFalse);

    // Another photo of the account stored under this id (a swap).
    final other = await a.store.addPhoto(
      plain.fakePhoto(50),
      mime: 'image/jpeg',
    );
    await a.media.uploadPending();
    final swapped = (await a.store.sealedForAccount(other, owner))!;
    server.mediaOf(owner)[id] = swapped;
    await expectLater(b.media.fetch(id), throwsA(isA<DecryptionFailed>()));

    final damaged = Uint8List.fromList(
      (await a.store.sealedForAccount(id, owner))!,
    )..[40] ^= 1;
    server.mediaOf(owner)[id] = damaged;
    await expectLater(b.media.fetch(id), throwsA(isA<DecryptionFailed>()));
    expect(b.store.hasFile(id), isFalse);
  });

  test('a 3 MiB file is encrypted and decrypted off the interface isolate, '
      'with the same format', () async {
    final big = plain.fakePhoto(3 * 1024 * 1024);
    final id = await a.store.addPhoto(big, mime: 'image/jpeg');
    expect(await a.store.read(id), big);
    await a.media.uploadPending();
    await metadataToB(id);
    expect(await b.media.fetch(id), isTrue);
    expect(await b.store.read(id), big);
  });
}
