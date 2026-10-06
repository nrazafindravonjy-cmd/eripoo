import 'dart:convert';
import 'dart:typed_data';

import 'package:eripoo/core/ids/ids.dart';
import 'package:eripoo/core/logging/app_logger.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/features/quest/data/progress_repository.dart';
import 'package:eripoo/features/quest/domain/step_progress.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:eripoo/security/envelopes.dart';
import 'package:eripoo/security/key_manager.dart';
import 'package:eripoo/sync/engine/conflict_resolution.dart';
import 'package:eripoo/sync/engine/sync_engine.dart';
import 'package:eripoo/sync/remote/sync_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/test_database.dart';

const owner = '0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a';

/// One phone or tablet of the same account.
class Device {
  Device(this.crypto, this.server, SecureKey umk, {this.pullPageSize = 200})
    : db = memoryDatabase(),
      deviceId = Ids.random(),
      keys = DataKeys(crypto, umk) {
    projects = ProjectRepository(db, clock: clock.call);
    progress = ProgressRepository(db, clock: clock.call);
  }

  final CryptoService crypto;
  final FakeSyncServer server;
  final AppDatabase db;
  final String deviceId;
  final DataKeys keys;
  final int pullPageSize;
  final clock = TestClock();
  final logs = MemoryLogSink();
  late final ProjectRepository projects;
  late final ProgressRepository progress;

  SyncEngine engine() => SyncEngine(
    db: db,
    remote: server.clientFor(owner),
    crypto: crypto,
    logger: AppLogger(sinks: [logs]),
    clock: clock.call,
    pullPageSize: pullPageSize,
  );

  SyncSession get session => SyncSession(
    ownerId: owner,
    deviceId: deviceId,
    recordKey: keys.records,
    umkVersion: 1,
  );

  Future<SyncReport> sync() => engine().runCycle(session);

  Future<int> pending() async => (await (db.select(
    db.syncMetaEntries,
  )..where((t) => t.changeId.isNotNull())).get()).length;

  Future<List<ConflictCopyRow>> conflictCopies() =>
      db.select(db.conflictCopies).get();

  Future<void> close() async {
    keys.dispose();
    await db.close();
  }
}

void main() {
  late CryptoService crypto;
  late FakeSyncServer server;
  late SecureKey umk;
  late Device a;
  late Device b;

  setUpAll(() async => crypto = await CryptoService.init());

  setUp(() {
    server = FakeSyncServer();
    umk = crypto.generateKey();
    a = Device(crypto, server, umk);
    b = Device(crypto, server, umk);
  });

  tearDown(() async {
    await a.close();
    await b.close();
    umk.dispose();
  });

  test(
    '1–2. offline work is kept, then synchronised when back online',
    () async {
      server.offline = true;
      for (final title in ['Épicerie', 'Couture', 'Jus de fruits']) {
        await a.projects.create(title);
      }
      final offline = await a.sync();
      expect(offline.complete, isFalse);
      expect(await a.pending(), 3);

      server.offline = false;
      a.clock.advance(const Duration(minutes: 2)); // past the retry delay
      expect((await a.sync()).complete, isTrue);
      expect(await a.pending(), 0);

      await b.sync();
      final titles = (await b.projects.watchActive().first).map((p) => p.title);
      expect(titles, unorderedEquals(['Épicerie', 'Couture', 'Jus de fruits']));
      expect(await b.pending(), 0);
    },
  );

  test('the server never receives readable content', () async {
    await a.projects.create('SENTINEL_TITRE_PRIVE');
    await a.sync();
    for (final record in server.recordsOf(owner).values) {
      expect(latin1.decode(record.payload!).contains('SENTINEL'), isFalse);
    }
  });

  test('a simple edit propagates without conflict', () async {
    final p = await a.projects.create('Épicerie');
    await a.sync();
    await b.sync();
    await b.projects.rename(p.id, 'Épicerie du marché');
    await b.sync();
    final report = await a.sync();
    expect(report.conflicts, 0);
    expect((await a.projects.get(p.id))!.title, 'Épicerie du marché');
  });

  test('3. concurrent edits: one version kept, the other set aside, both devices converge', () async {
    final p = await a.projects.create('Épicerie');
    await a.sync();
    await b.sync();

    await a.projects.rename(p.id, 'Version A');
    await b.projects.rename(p.id, 'Version B');
    await a.sync(); // A first
    final report = await b.sync(); // B meets the conflict
    expect(report.conflicts, greaterThan(0));
    await a.sync();
    await b.sync();

    final titleA = (await a.projects.get(p.id))!.title;
    final titleB = (await b.projects.get(p.id))!.title;
    expect(titleA, titleB, reason: 'devices converge');
    expect(
      titleB,
      'Version B',
      reason: 'the resolving device keeps its version',
    );

    for (final device in [a, b]) {
      final copies = await device.conflictCopies();
      expect(copies, hasLength(1));
      final aside =
          jsonDecode(copies.single.payloadJson) as Map<String, Object?>;
      expect(
        aside['title'],
        'Version A',
        reason: 'the other version is not lost',
      );
    }
    expect(await a.pending(), 0);
    expect(await b.pending(), 0);
  });

  test(
    '4. deletion vs concurrent edit: deleted, and the trash keeps the edit',
    () async {
      final p = await a.projects.create('Épicerie');
      await a.sync();
      await b.sync();

      await a.projects.moveToTrash(p.id);
      await b.projects.rename(p.id, 'Épicerie modifiée');
      await a.sync();
      await b.sync();
      await a.sync();

      for (final device in [a, b]) {
        final project = (await device.projects.get(p.id))!;
        expect(project.isDeleted, isTrue);
        expect(project.title, 'Épicerie modifiée');
      }
    },
  );

  test('5. response lost after the server applied the push: no duplicate, no false conflict', () async {
    final p = await a.projects.create('Épicerie');
    server.loseNextPushResponse = true;
    expect((await a.sync()).complete, isFalse);
    expect(server.recordsOf(owner), hasLength(1)); // applied server side

    // The user edits again before the next cycle, and the app restarts.
    await a.projects.rename(p.id, 'Épicerie v2');
    a.clock.advance(const Duration(minutes: 2));
    final report = await a.sync(); // new engine instance
    expect(report.conflicts, 0);
    expect(await a.conflictCopies(), isEmpty);
    expect(await a.pending(), 0);

    await b.sync();
    expect((await b.projects.get(p.id))!.title, 'Épicerie v2');
  });

  test('5b. response lost and replayed as is: idempotent', () async {
    await a.projects.create('Épicerie');
    server.loseNextPushResponse = true;
    await a.sync();
    final versionBefore = server.recordsOf(owner).values.single.version;
    a.clock.advance(const Duration(minutes: 2));
    await a.sync();
    expect(server.recordsOf(owner).values.single.version, versionBefore);
    expect(await a.pending(), 0);
  });

  test(
    '6. pull interrupted between pages: cursor never ahead of the data',
    () async {
      final reader = Device(crypto, server, umk, pullPageSize: 2);
      addTearDown(reader.close);
      for (var i = 0; i < 5; i++) {
        await a.projects.create('Projet $i');
      }
      await a.sync();

      server.failPullAfter(1);
      expect((await reader.sync()).complete, isFalse);
      final cursor = int.parse((await reader.db.readValue('sync.cursor'))!);
      final applied = await reader.db.select(reader.db.projects).get();
      expect(applied, hasLength(cursor)); // exactly what the cursor covers

      expect((await reader.sync()).complete, isTrue);
      expect(await reader.db.select(reader.db.projects).get(), hasLength(5));
    },
  );

  test(
    '7. sync can resume after a crash at any point (fresh engine each time)',
    () async {
      for (var i = 0; i < 3; i++) {
        await a.projects.create('Projet $i');
      }
      server.offline = true;
      await a.sync();
      server.offline = false;
      a.clock.advance(const Duration(hours: 2));
      await a.sync();
      await b.sync();
      expect(await b.db.select(b.db.projects).get(), hasLength(3));
    },
  );

  test('9. wrong device clocks do not change who wins', () async {
    final p = await a.projects.create('Épicerie');
    await a.sync();
    await b.sync();
    b.clock.now = DateTime.utc(2029); // B's clock far in the future
    a.clock.now = DateTime.utc(2020); // A's clock in the past
    await b.projects.rename(p.id, 'B');
    await a.projects.rename(p.id, 'A');
    await b.sync();
    await a.sync(); // A resolves: A's version kept, regardless of clocks
    await b.sync();
    expect((await a.projects.get(p.id))!.title, 'A');
    expect((await b.projects.get(p.id))!.title, 'A');
  });

  test('progress merges to the most advanced status', () async {
    await a.progress.setStatus('q01', 'q01.s01', StepStatus.inProgress);
    await a.sync();
    await b.sync();
    await a.progress.setStatus('q01', 'q01.s01', StepStatus.completed);
    await b.progress.setStatus('q01', 'q01.s01', StepStatus.deferred);
    await a.sync();
    await b.sync();
    await a.sync();
    expect((await a.progress.get('q01.s01'))!.status, StepStatus.completed);
    expect((await b.progress.get('q01.s01'))!.status, StepStatus.completed);
    expect(await b.conflictCopies(), isEmpty);
  });

  test(
    'history entries (append-only) from both devices are all kept',
    () async {
      final p = await a.projects.create('Projet');
      await a.sync();
      await b.sync();
      await a.projects.saveSection(
        projectId: p.id,
        sectionKey: 'vision',
        fields: {'statement': 'A'},
        trackedFields: {'statement'},
      );
      await b.projects.saveSection(
        projectId: p.id,
        sectionKey: 'problem',
        fields: {'statement': 'B'},
        trackedFields: {'statement'},
      );
      await a.sync();
      await b.sync();
      await a.sync();
      expect(await a.projects.history(p.id), hasLength(2));
      expect(await b.projects.history(p.id), hasLength(2));
    },
  );

  test(
    '12. records written by a newer app version are left untouched',
    () async {
      await a.sync(); // registers A
      await b.sync();
      final id = Ids.newId();
      final payload = RecordEnvelopes(crypto).seal(
        plaintext: Uint8List.fromList(
          utf8.encode(
            jsonEncode({'t': 'project', 's': 99, 'd': <String, Object?>{}}),
          ),
        ),
        recordKey: a.keys.records,
        umkVersion: 1,
        ownerId: owner,
        recordId: id,
      );
      await server.clientFor(owner).push(a.deviceId, [
        RemotePut(
          id: id,
          changeId: Ids.random(),
          baseVersion: null,
          deleted: false,
          umkVersion: 1,
          payload: payload,
        ),
      ]);
      await b.sync();
      expect(await b.db.select(b.db.projects).get(), isEmpty);
      expect(server.recordsOf(owner)[id], isNotNull);
      expect(
        b.logs.records.map((r) => r.event),
        contains('SyncLog.unknownSchema'),
      );
    },
  );

  test(
    'a device with another key cannot read anything and does not crash',
    () async {
      await a.projects.create('Projet');
      await a.sync();
      final otherKey = crypto.generateKey();
      final stranger = Device(crypto, server, otherKey);
      addTearDown(() async {
        await stranger.close();
        otherKey.dispose();
      });
      await stranger.sync();
      expect(await stranger.db.select(stranger.db.projects).get(), isEmpty);
      expect(
        stranger.logs.records.map((r) => r.event),
        contains('SyncLog.undecryptableRecord'),
      );
    },
  );

  test('13. a revoked device is told to stop', () async {
    await a.projects.create('Projet');
    await a.sync();
    server.revoke(owner, a.deviceId);
    await expectLater(a.sync(), throwsA(isA<DeviceRevoked>()));
  });

  test('14. 500 changes go through in batches without loss', () async {
    for (var i = 0; i < 500; i++) {
      await a.projects.create('Projet $i');
    }
    final watch = Stopwatch()..start();
    await a.sync();
    await b.sync();
    watch.stop();
    expect(await b.db.select(b.db.projects).get(), hasLength(500));
    expect(server.pushCalls, greaterThanOrEqualTo(10)); // batches of 50
    // Development machine only; device performance is NOT VERIFIED (P7).
    // ignore: avoid_print
    print('500 records synced A→server→B in ${watch.elapsedMilliseconds} ms');
  });

  group('conflict resolution rules (pure)', () {
    test('identical content is not set aside', () {
      final outcome = resolveConflict(
        entityType: 'project',
        local: {'id': '1', 'title': 'x', 'updatedAt': 1},
        remote: {'id': '1', 'title': 'x', 'updatedAt': 2},
      );
      expect(outcome.setAside, isNull);
    });

    test('families', () {
      expect(familyOf('project_revision'), EntityFamily.appendOnly);
      expect(familyOf('conflict_copy'), EntityFamily.appendOnly);
      expect(familyOf('step_progress'), EntityFamily.progress);
      expect(familyOf('project'), EntityFamily.editable);
    });
  });
}
