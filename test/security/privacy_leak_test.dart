import 'dart:convert';
import 'dart:io';

import 'package:eripoo/app/startup/app_services.dart';
import 'package:eripoo/core/logging/app_logger.dart';
import 'package:eripoo/features/account/application/account_linker.dart';
import 'package:eripoo/features/profile/data/profile_repository.dart';
import 'package:eripoo/features/profile/domain/user_profile.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/security/envelopes.dart';
import 'package:eripoo/security/key_manager.dart';
import 'package:eripoo/sync/engine/sync_engine.dart';
import 'package:eripoo/sync/remote/supabase_sync_remote.dart';
import 'package:eripoo/sync/remote/sync_remote.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/memory_secure_store.dart';

/// Private project content, recognisable anywhere it might leak.
const sentinel = 'QXZ-SENTINELLE-Épicerie-7b1';
const owner = '0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a';

/// Wraps a remote and keeps the exact JSON body of every RPC call, as
/// SupabaseSyncRemote would send it.
class RecordingRemote implements SyncRemote {
  RecordingRemote(this._inner);
  final SyncRemote _inner;
  final bodies = <String>[];
  final errors = <Object>[];

  Future<T> _call<T>(Object? body, Future<T> Function() call) async {
    bodies.add(jsonEncode(body));
    try {
      return await call();
    } on Object catch (e) {
      errors.add(e);
      rethrow;
    }
  }

  @override
  Future<void> registerDevice(String id, String label, {String? appVersion}) =>
      _call({
        'p_device_id': id,
        'p_label': label,
        'p_app_version': appVersion,
      }, () => _inner.registerDevice(id, label, appVersion: appVersion));

  @override
  Future<List<PushResult>> push(String deviceId, List<RemotePut> puts) =>
      _call({
        'p_device_id': deviceId,
        'p_puts': [for (final p in puts) encodePut(p)],
      }, () => _inner.push(deviceId, puts));

  @override
  Future<PullPage> pull(String deviceId, int since, {int limit = 200}) => _call(
    {'p_device_id': deviceId, 'p_since': since, 'p_limit': limit},
    () => _inner.pull(deviceId, since, limit: limit),
  );

  @override
  Future<void> setRecoveryWrap(RecoveryWrap wrap) => _call({
    'p_wrap_id': wrap.wrapId,
    'p_salt': base64.encode(wrap.salt),
    'p_kdf_params': wrap.params.toJson(),
    'p_wrapped': base64.encode(wrap.wrapped),
  }, () => _inner.setRecoveryWrap(wrap));

  @override
  Future<RecoveryWrap?> getRecoveryWrap() =>
      _call(const {}, _inner.getRecoveryWrap);

  @override
  Future<void> revokeDevice(String deviceId) =>
      _call({'p_device_id': deviceId}, () => _inner.revokeDevice(deviceId));

  @override
  Future<List<RemoteDevice>> listDevices({String? currentDeviceId}) => _call({
    'p_current_device': currentDeviceId,
  }, () => _inner.listDevices(currentDeviceId: currentDeviceId));
}

void expectNoSentinel(String where, Iterable<String> texts) {
  for (final text in texts) {
    expect(
      text.contains(sentinel) ||
          text.contains(base64.encode(utf8.encode(sentinel))),
      isFalse,
      reason: 'private content found in $where',
    );
  }
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('eripoo_leak'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('private content never reaches logs, errors, RPC bodies or files '
      'other than the encrypted database', () async {
    final sink = MemoryLogSink();
    final logger = AppLogger(sinks: [sink]);
    final store = MemorySecureKeyStore();
    final file = File('${dir.path}/eripoo.sqlite');
    final services = await AppServices.start(store, file: file);
    final db = services.database;
    final caught = <Object>[];

    // Private content everywhere a user can type.
    final projects = ProjectRepository(db);
    final project = await projects.create('Projet $sentinel');
    await projects.saveSection(
      projectId: project.id,
      sectionKey: 'problem',
      fields: {'statement': 'Constat : $sentinel'},
      trackedFields: {'statement'},
    );
    await ProfileRepository(db)
        .save(const UserProfile(displayName: 'Hery $sentinel'));
    // Validation errors on private input.
    try {
      await projects.create('$sentinel ${'x' * 500}');
    } on Object catch (e) {
      caught.add(e);
    }
    try {
      await ProfileRepository(db)
          .save(UserProfile(displayName: '$sentinel ${'y' * 100}'));
    } on Object catch (e) {
      caught.add(e);
    }

    // Account link and sync, with failures on the way.
    final server = FakeSyncServer();
    final remote = RecordingRemote(server.clientFor(owner));
    final link = await AccountLinker(
      db: db,
      keyManager: services.keyManager,
      remote: remote,
    ).link(ownerId: owner, localKeys: services.keys);
    expect(link, isA<NewAccountLinked>());
    final key = DataKeys(services.crypto, services.keys.dataKey).records;
    addTearDown(key.dispose);
    final session = SyncSession(
      ownerId: owner,
      deviceId: services.keys.deviceId,
      recordKey: key,
      umkVersion: 1,
    );
    SyncEngine engine() => SyncEngine(
      db: db,
      remote: remote,
      crypto: services.crypto,
      logger: logger,
    );
    server.offline = true;
    await engine().runCycle(session);
    server.offline = false;
    server.loseNextPushResponse = true;
    await engine().runCycle(session);
    await engine().runCycle(session);
    // An undecryptable record from the server (logged as such).
    await server.clientFor(owner).push(services.keys.deviceId, [
      RemotePut(
        id: '0192f2a0-7c1e-7b3a-9c2d-00000000beef',
        changeId: '0192f2a0-7c1e-7b3a-9c2d-00000000cafe',
        baseVersion: null,
        deleted: false,
        umkVersion: 1,
        payload: utf8.encode('garbage'),
      ),
    ]);
    await engine().runCycle(session);
    await db.close();

    // RPC bodies: identifiers and ciphertext only.
    expect(remote.bodies, isNotEmpty);
    expectNoSentinel('RPC bodies', remote.bodies);
    // Logs, as stored and as rendered for the console.
    expect(sink.records, isNotEmpty);
    expectNoSentinel('logs', [
      for (final r in sink.records) ...[
        r.render(),
        ...r.fields.values,
        r.errorType ?? '',
      ],
    ]);
    // Exceptions, as they would be printed or reported.
    expect(caught, hasLength(2));
    expectNoSentinel('exceptions', [
      for (final e in [...caught, ...remote.errors]) e.toString(),
    ]);
    // Files: only the database and its WAL, never readable in clear.
    final names = dir.listSync().map((e) => e.uri.pathSegments.last).toSet();
    expect(
      names.difference({
        'eripoo.sqlite',
        'eripoo.sqlite-wal',
        'eripoo.sqlite-shm',
      }),
      isEmpty,
      reason: 'no temporary or extra file',
    );
    for (final f in dir.listSync().whereType<File>()) {
      final bytes = f.readAsBytesSync();
      expectNoSentinel(f.path, [latin1.decode(bytes)]);
      expect(
        latin1.decode(bytes).contains(latin1.decode(utf8.encode(sentinel))),
        isFalse,
        reason: '${f.path} contains plaintext',
      );
    }
    // Keystore entries hold keys and ids, never content.
    expectNoSentinel('secure storage', store.values.values);
  });
}
