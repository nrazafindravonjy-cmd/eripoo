import 'dart:typed_data';

import 'package:eripoo/security/envelopes.dart';
import 'package:eripoo/sync/remote/sync_remote.dart';

/// In-memory test double of the server functions (supabase/migrations),
/// with the same contract: per-user contiguous versions, change_id
/// idempotency, conflicts on stale base, tombstones, devices. The real SQL
/// is checked against the same rules in supabase/tests/sql.
class FakeSyncServer {
  final _records = <String, Map<String, RemoteRecord>>{}; // owner → id → record
  final _heads = <String, int>{};
  final _devices = <String, Map<String, String>>{}; // owner → device → status
  final _wraps = <String, RecoveryWrap>{};

  /// Fault injection.
  bool offline = false;
  bool loseNextPushResponse = false; // applied on the server, response lost
  int _failPullAfterPages = -1;
  int _pullPages = 0;

  /// The next pulls succeed for [pages] pages, then one pull fails.
  void failPullAfter(int pages) {
    _failPullAfterPages = pages;
    _pullPages = 0;
  }

  int pushCalls = 0;

  FakeSyncRemote clientFor(String ownerId) => FakeSyncRemote(this, ownerId);

  Map<String, RemoteRecord> recordsOf(String owner) =>
      _records[owner] ?? const {};

  void revoke(String owner, String deviceId) =>
      (_devices[owner] ??= {})[deviceId] = 'revoked';

  void _requireDevice(String owner, String deviceId) {
    final status = _devices[owner]?[deviceId];
    if (status == null) throw const DeviceUnknown();
    if (status == 'revoked') throw const DeviceRevoked();
  }
}

class FakeSyncRemote implements SyncRemote {
  FakeSyncRemote(this.server, this.ownerId);

  final FakeSyncServer server;
  final String ownerId;

  void _online() {
    if (server.offline) throw const RemoteUnavailable();
  }

  @override
  Future<void> registerDevice(
    String deviceId,
    String label, {
    String? appVersion,
  }) async {
    _online();
    final devices = server._devices[ownerId] ??= {};
    if (devices[deviceId] == 'revoked') throw const DeviceRevoked();
    if (devices[deviceId] == null &&
        devices.values.where((s) => s == 'active').length >= 5) {
      throw const DeviceLimitReached();
    }
    devices[deviceId] = 'active';
  }

  @override
  Future<List<PushResult>> push(String deviceId, List<RemotePut> puts) async {
    _online();
    server.pushCalls++;
    server._requireDevice(ownerId, deviceId);
    if (puts.length > 50) throw const RemoteRejected();
    final records = server._records[ownerId] ??= {};
    var head = server._heads[ownerId] ?? 0;
    final results = <PushResult>[];
    for (final put in puts) {
      if (put.payload == null && !put.deleted) {
        results.add(PushRejected(put.id, 'invalid_put'));
        continue;
      }
      final row = records[put.id];
      if (row != null && row.changeId == put.changeId) {
        results.add(PushApplied(put.id, row.version));
      } else if ((row != null &&
              (put.baseVersion == null || row.version != put.baseVersion)) ||
          (row == null && put.baseVersion != null)) {
        results.add(PushConflict(put.id, row));
      } else {
        head++;
        records[put.id] = RemoteRecord(
          id: put.id,
          version: head,
          changeId: put.changeId,
          deviceId: deviceId,
          deleted: put.deleted,
          umkVersion: put.umkVersion,
          payload: put.payload == null
              ? null
              : Uint8List.fromList(put.payload!),
        );
        results.add(PushApplied(put.id, head));
      }
    }
    server._heads[ownerId] = head;
    if (server.loseNextPushResponse) {
      server.loseNextPushResponse = false;
      throw const RemoteUnavailable();
    }
    return results;
  }

  @override
  Future<PullPage> pull(String deviceId, int since, {int limit = 200}) async {
    _online();
    server._requireDevice(ownerId, deviceId);
    if (server._failPullAfterPages >= 0 &&
        server._pullPages >= server._failPullAfterPages) {
      server._failPullAfterPages = -1;
      server._pullPages = 0;
      throw const RemoteUnavailable();
    }
    server._pullPages++;
    final records = (server._records[ownerId]?.values.toList() ?? [])
      ..sort((a, b) => a.version.compareTo(b.version));
    return PullPage(
      head: server._heads[ownerId] ?? 0,
      records: records.where((r) => r.version > since).take(limit).toList(),
    );
  }

  @override
  Future<void> setRecoveryWrap(RecoveryWrap wrap) async {
    _online();
    server._wraps[ownerId] = wrap;
  }

  @override
  Future<RecoveryWrap?> getRecoveryWrap() async {
    _online();
    return server._wraps[ownerId];
  }
}
