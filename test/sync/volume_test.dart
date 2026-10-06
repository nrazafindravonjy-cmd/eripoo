@Tags(['volume'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:eripoo/app/startup/app_services.dart';
import 'package:eripoo/core/logging/app_logger.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/security/key_manager.dart';
import 'package:eripoo/sync/engine/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/memory_secure_store.dart';

const owner = '0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a';
const count = 5000;

/// Measurements are printed as `MEASURE <name> <value>` lines and copied
/// into docs/OFFLINE_SYNC.md §13.2 (development machine, not a phone).
void measure(String name, Object value) =>
    stdout.writeln('MEASURE $name $value');

int fileSize(File f) {
  var total = 0;
  for (final suffix in ['', '-wal']) {
    final file = File('${f.path}$suffix');
    if (file.existsSync()) total += file.lengthSync();
  }
  return total;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('eripoo_volume'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('14. 5 000 items: written offline, synced through cuts, no duplicate '
      'and no loss', () async {
    final server = FakeSyncServer();
    final fileA = File('${dir.path}/a.sqlite');
    final fileB = File('${dir.path}/b.sqlite');
    final a = await AppServices.start(MemorySecureKeyStore(), file: fileA);
    final b = await AppServices.start(MemorySecureKeyStore(), file: fileB);
    addTearDown(() async {
      await a.database.close();
      await b.database.close();
    });
    final recordKey = DataKeys(a.crypto, a.keys.dataKey).records;
    SyncSession session(AppServices s) => SyncSession(
      ownerId: owner,
      deviceId: s.keys.deviceId,
      recordKey: recordKey,
      umkVersion: 1,
    );
    SyncEngine engine(AppServices s) => SyncEngine(
      db: s.database,
      remote: server.clientFor(owner, session: s.keys.deviceId),
      crypto: s.crypto,
      logger: AppLogger(sinks: const []),
    );
    final rssStart = ProcessInfo.currentRss;

    // Local writes, one transaction each (as the app does), offline.
    final projects = ProjectRepository(a.database);
    final watch = Stopwatch()..start();
    for (var i = 0; i < count; i++) {
      await projects.create('Projet numéro $i');
    }
    watch.stop();
    measure('local_write_total_ms', watch.elapsedMilliseconds);
    measure(
      'local_write_per_item_ms',
      (watch.elapsedMicroseconds / count / 1000).toStringAsFixed(2),
    );
    await a.database.customStatement('pragma wal_checkpoint(truncate)');
    measure('db_size_kib_after_writes', fileSize(fileA) ~/ 1024);

    // Push with two cuts: one request lost before the server, one
    // response lost after the server applied the batch.
    watch
      ..reset()
      ..start();
    server.failPushAfter(30);
    final first = await engine(a).runCycle(session(a));
    expect(first.complete, isFalse);
    server.loseNextPushResponse = true;
    final second = await engine(a).runCycle(session(a));
    expect(second.complete, isFalse);
    var cycles = 2;
    while (!(await engine(a).runCycle(session(a))).complete) {
      cycles++;
    }
    cycles++;
    watch.stop();
    measure('push_total_ms', watch.elapsedMilliseconds);
    measure('push_cycles', cycles);
    measure('push_batches_sent', server.pushCalls);

    // No duplicate: exactly one server version per item.
    expect(server.recordsOf(owner), hasLength(count));
    expect(server.headOf(owner), count);
    final pending = await (a.database.select(
      a.database.syncMetaEntries,
    )..where((t) => t.changeId.isNotNull())).get();
    expect(pending, isEmpty);

    // Pull on a second device, cut in the middle.
    watch
      ..reset()
      ..start();
    server.failPullAfter(10);
    expect((await engine(b).runCycle(session(b))).complete, isFalse);
    final partial = await b.database.select(b.database.projects).get();
    expect(partial.length, lessThan(count));
    expect((await engine(b).runCycle(session(b))).complete, isTrue);
    watch.stop();
    measure('pull_total_ms', watch.elapsedMilliseconds);

    // No loss, no duplicate, same content.
    final titlesA = {
      for (final p in await a.database.select(a.database.projects).get())
        p.id: p.title,
    };
    final rowsB = await b.database.select(b.database.projects).get();
    expect(rowsB, hasLength(count));
    expect({for (final p in rowsB) p.id: p.title}, titlesA);
    expect(await b.database.select(b.database.conflictCopies).get(), isEmpty);

    await b.database.customStatement('pragma wal_checkpoint(truncate)');
    measure('db_size_kib_receiver', fileSize(fileB) ~/ 1024);
    measure('rss_growth_mib', (ProcessInfo.currentRss - rssStart) >> 20);
    measure('max_rss_mib', ProcessInfo.maxRss >> 20);
    recordKey.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
