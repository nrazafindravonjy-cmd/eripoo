import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../security/crypto_service.dart';
import '../../security/envelopes.dart';
import 'sync_remote.dart';

/// [SyncRemote] over Supabase RPC.
///
/// ⚠️ NOT VERIFIED against a running Supabase (no development project yet).
/// The server side is tested in SQL; the JSON mapping here is unit-tested.
class SupabaseSyncRemote implements SyncRemote {
  SupabaseSyncRemote(this._client);

  final SupabaseClient _client;

  Future<Object?> _rpc(String name, Map<String, Object?> params) async {
    try {
      return await _client.rpc<Object?>(name, params: params);
    } on PostgrestException catch (e) {
      throw mapRemoteError(e.message);
    } on Exception {
      throw const RemoteUnavailable();
    }
  }

  @override
  Future<void> registerDevice(
    String deviceId,
    String label, {
    String? appVersion,
  }) => _rpc('register_device', {
    'p_device_id': deviceId,
    'p_label': label,
    'p_app_version': appVersion,
  });

  @override
  Future<List<PushResult>> push(String deviceId, List<RemotePut> puts) async {
    final result = await _rpc('sync_push', {
      'p_device_id': deviceId,
      'p_puts': [for (final put in puts) encodePut(put)],
    });
    return [
      for (final item in result! as List<Object?>)
        decodePushResult(item! as Map<String, Object?>),
    ];
  }

  @override
  Future<PullPage> pull(String deviceId, int since, {int limit = 200}) async {
    final result = await _rpc('sync_pull', {
      'p_device_id': deviceId,
      'p_since': since,
      'p_limit': limit,
    });
    return decodePullPage(result! as Map<String, Object?>);
  }

  @override
  Future<void> setRecoveryWrap(RecoveryWrap wrap) => _rpc('set_recovery_wrap', {
    'p_wrap_id': wrap.wrapId,
    'p_umk_version': wrap.umkVersion,
    'p_salt': base64.encode(wrap.salt),
    'p_kdf_params': wrap.params.toJson(),
    'p_wrapped': base64.encode(wrap.wrapped),
  });

  @override
  Future<RecoveryWrap?> getRecoveryWrap() async {
    final result = await _rpc('get_recovery_wrap', const {});
    if (result == null) return null;
    final json = result as Map<String, Object?>;
    return RecoveryWrap(
      wrapId: json['wrap_id']! as String,
      umkVersion: json['umk_version']! as int,
      salt: base64.decode(json['salt']! as String),
      params: KdfParams.fromJson(json['kdf_params']! as Map<String, Object?>),
      wrapped: base64.decode(json['wrapped']! as String),
    );
  }
}

/// Server error messages are fixed codes raised by the SQL functions.
SyncRemoteFailure mapRemoteError(String message) {
  for (final (code, failure) in const [
    ('not_authenticated', NotAuthenticated()),
    ('device_revoked', DeviceRevoked()),
    ('device_unknown', DeviceUnknown()),
    ('device_limit', DeviceLimitReached()),
    ('rate_limited', RateLimited()),
    ('reauthentication_required', ReauthenticationRequired()),
    ('batch_too_large', RemoteRejected()),
    ('invalid_batch', RemoteRejected()),
    ('invalid_base64', RemoteRejected()),
    ('kdf_params_too_weak', RemoteRejected()),
  ]) {
    if (message.contains(code)) return failure;
  }
  return const RemoteUnavailable();
}

Map<String, Object?> encodePut(RemotePut put) => {
  'id': put.id,
  'change_id': put.changeId,
  'base_version': put.baseVersion,
  'deleted': put.deleted,
  'umk_version': put.umkVersion,
  'payload': put.payload == null ? null : base64.encode(put.payload!),
};

RemoteRecord decodeRecord(Map<String, Object?> json, {String? id}) {
  final payload = json['payload'] as String?;
  return RemoteRecord(
    id: id ?? json['id']! as String,
    version: (json['version']! as num).toInt(),
    changeId: json['change_id']! as String,
    deviceId: json['device_id']! as String,
    deleted: json['deleted']! as bool,
    umkVersion: (json['umk_version']! as num).toInt(),
    payload: payload == null
        ? null
        : Uint8List.fromList(base64.decode(payload)),
  );
}

PushResult decodePushResult(Map<String, Object?> json) {
  final id = json['id'] as String? ?? '';
  return switch (json['status']) {
    'applied' => PushApplied(id, (json['version']! as num).toInt()),
    'conflict' => PushConflict(
      id,
      json['current'] == null
          ? null
          : decodeRecord(json['current']! as Map<String, Object?>, id: id),
    ),
    _ => PushRejected(id, json['reason'] as String? ?? 'unknown'),
  };
}

PullPage decodePullPage(Map<String, Object?> json) => PullPage(
  head: (json['head']! as num).toInt(),
  records: [
    for (final r in json['records']! as List<Object?>)
      decodeRecord(r! as Map<String, Object?>),
  ],
);
