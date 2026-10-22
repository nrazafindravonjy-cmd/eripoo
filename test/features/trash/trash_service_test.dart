// The trash between two phones (docs/OFFLINE_SYNC.md §7): delete, restore
// and delete forever travel through the server; a purge leaves only a
// tombstone without content; 30 days later it happens by itself; a restore
// on another phone wins over a purge. Fictitious data only.
import 'dart:io';

import 'package:eripoo/core/ids/ids.dart';
import 'package:eripoo/core/logging/app_logger.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/hypotheses/application/research_service.dart';
import 'package:eripoo/features/hypotheses/domain/hypothesis_states.dart';
import 'package:eripoo/features/media/application/media_sync.dart';
import 'package:eripoo/features/media/data/media_store.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/features/trash/application/trash_service.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:eripoo/security/key_manager.dart';
import 'package:eripoo/sync/engine/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../helpers/fake_sync_server.dart';
import '../../helpers/test_database.dart';
import '../media/media_store_test.dart' as plain;

const owner = '0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a';

class Phone {
  Phone(CryptoService crypto, SecureKey umk, this.server)
    : db = memoryDatabase(),
      dir = Directory.systemTemp.createTempSync('eripoo_trash'),
      deviceId = Ids.random(),
      keys = DataKeys(crypto, umk) {
    store = MediaStore(
      db: db,
      crypto: crypto,
      key: keys.media,
      umkVersion: 1,
      dir: dir,
    );
    engine = SyncEngine(
      db: db,
      remote: server.clientFor(owner, session: deviceId),
      crypto: crypto,
      logger: AppLogger(sinks: const []),
    );
  }

  final FakeSyncServer server;
  final AppDatabase db;
  final Directory dir;
  final String deviceId;
  final DataKeys keys;
  final clock = TestClock();
  late final MediaStore store;
  late final SyncEngine engine;

  TrashService get trash => TrashService(db, media: store, clock: clock.call);
  ResearchService get research => ResearchService(db);
  MediaSync get media => MediaSync(
    db: db,
    store: store,
    remote: server.mediaFor(owner, session: deviceId),
    ownerId: owner,
  );

  Future<SyncReport> sync() => engine.runCycle(
    SyncSession(
      ownerId: owner,
      deviceId: deviceId,
      recordKey: keys.records,
      umkVersion: 1,
    ),
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
  late String project;

  setUpAll(() async => crypto = await CryptoService.init());
  setUp(() async {
    umk = crypto.generateKey();
    server = FakeSyncServer();
    a = Phone(crypto, umk, server);
    b = Phone(crypto, umk, server);
    project = (await ProjectRepository(a.db).create('Savon du quartier')).id;
  });
  tearDown(() async {
    await a.close();
    await b.close();
    umk.dispose();
  });

  Future<String> note(Phone p, String text) async =>
      (await p.research.addObservation(
        projectId: project,
        description: text,
      )).id;

  test('deleted here, in the trash there; restored there, back here', () async {
    final id = await note(a, 'File d\'attente à la fontaine.');
    await a.sync();
    await b.sync();

    await a.trash.moveToTrash(TrashKind.observation, id);
    await a.sync();
    await b.sync();
    expect((await b.research.observationsOf(project)), isEmpty);
    final inTrash = (await b.trash.items()).single;
    expect(inTrash.label, 'File d\'attente à la fontaine.');
    expect(
      inTrash.purgeAt.difference(inTrash.deletedAt),
      const Duration(days: 30),
    );

    await b.trash.restore(TrashKind.observation, id);
    await b.sync();
    await a.sync();
    expect((await a.research.observationsOf(project)), hasLength(1));
    expect(await a.trash.items(), isEmpty);
  });

  test(
    'deleted forever: a tombstone without content, gone on both phones',
    () async {
      final id = await note(a, 'Note privée');
      await a.sync();
      await b.sync();
      await a.trash.moveToTrash(TrashKind.observation, id);
      await a.trash.purge(TrashKind.observation, id);
      expect(await a.trash.items(), isEmpty, reason: 'hidden at once');
      expect(
        await a.db.select(a.db.observations).get(),
        hasLength(1),
        reason: 'kept until the server confirmed',
      );

      await a.sync();
      final tomb = server.recordsOf(owner)[id]!;
      expect(tomb.deleted, isTrue);
      expect(tomb.payload, isNull);
      expect(await a.db.select(a.db.observations).get(), isEmpty);
      await b.sync();
      expect(await b.db.select(b.db.observations).get(), isEmpty);
      expect((await a.sync()).complete, isTrue);
    },
  );

  test(
    'never sent: deleted forever at once, nothing reaches the server',
    () async {
      final id = await note(a, 'Brouillon');
      await a.trash.moveToTrash(TrashKind.observation, id);
      await a.trash.purge(TrashKind.observation, id);
      expect(await a.db.select(a.db.observations).get(), isEmpty);
      await a.sync();
      expect(server.recordsOf(owner)[id], isNull);
    },
  );

  test('a photo evidence goes to the trash, comes back, and is deleted '
      'forever with its file and its server copy', () async {
    final mediaId = await a.store.addPhoto(
      plain.fakePhoto(),
      mime: 'image/jpeg',
    );
    final evidence = await a.research.addEvidence(
      projectId: project,
      subject: EvidenceSubject.observation,
      subjectId: await note(a, 'Étal'),
      kind: EvidenceKind.photo,
      mediaId: mediaId,
    );
    await a.sync();
    await a.media.uploadPending();
    expect(server.mediaOf(owner), hasLength(1));

    await a.trash.moveToTrash(TrashKind.evidence, evidence.id);
    expect(a.store.hasFile(mediaId), isTrue, reason: 'restorable');
    await a.trash.restore(TrashKind.evidence, evidence.id);
    expect(await a.store.read(mediaId), isNotNull);

    await a.trash.moveToTrash(TrashKind.evidence, evidence.id);
    await a.trash.purge(TrashKind.evidence, evidence.id);
    expect(a.store.hasFile(mediaId), isFalse);
    await a.sync();
    expect(await a.media.deleteRemoved(), 1);
    expect(server.mediaOf(owner), isEmpty);
    expect(server.recordsOf(owner)[mediaId]!.payload, isNull);
  });

  test('after 30 days the trash empties itself', () async {
    final old = await note(a, 'Ancienne');
    final recent = await note(a, 'Récente');
    await a.sync();
    await a.trash.moveToTrash(TrashKind.observation, old);
    a.clock.advance(const Duration(days: 20));
    await a.trash.moveToTrash(TrashKind.observation, recent);
    a.clock.advance(const Duration(days: 11)); // old: 31 days, recent: 11
    expect(await a.trash.purgeExpired(), 1);
    expect((await a.trash.items()).single.id, recent);
  });

  test('restored on another phone while deleted forever here: the restore '
      'wins, nothing is lost', () async {
    final id = await note(a, 'À garder finalement');
    await a.sync();
    await a.trash.moveToTrash(TrashKind.observation, id);
    await a.sync();
    await b.sync();

    await b.trash.restore(TrashKind.observation, id);
    await b.sync();
    await a.trash.purge(TrashKind.observation, id); // A has not seen it yet
    await a.sync();
    await b.sync();
    for (final p in [a, b]) {
      final notes = (await p.research.observationsOf(project));
      expect(notes.single.description, 'À garder finalement');
    }
    expect(server.recordsOf(owner)[id]!.payload, isNotNull);
  });
}
