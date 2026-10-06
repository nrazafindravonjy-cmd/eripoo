import 'dart:typed_data';

import '../../security/envelopes.dart';

/// One encrypted envelope sent to the server (docs/OFFLINE_SYNC.md §4).
class RemotePut {
  const RemotePut({
    required this.id,
    required this.changeId,
    required this.baseVersion,
    required this.deleted,
    required this.umkVersion,
    required this.payload,
  });

  final String id;
  final String changeId;
  final int? baseVersion;
  final bool deleted;
  final int umkVersion;

  /// Encrypted envelope; null only for a purged (deleted) record.
  final Uint8List? payload;
}

/// The server state of one record.
class RemoteRecord {
  const RemoteRecord({
    required this.id,
    required this.version,
    required this.changeId,
    required this.deviceId,
    required this.deleted,
    required this.umkVersion,
    required this.payload,
  });

  final String id;
  final int version;
  final String changeId;
  final String deviceId;
  final bool deleted;
  final int umkVersion;
  final Uint8List? payload;
}

sealed class PushResult {
  const PushResult(this.id);
  final String id;
}

final class PushApplied extends PushResult {
  const PushApplied(super.id, this.version);
  final int version;
}

final class PushConflict extends PushResult {
  const PushConflict(super.id, this.current);

  /// Null when the server has no record for this id.
  final RemoteRecord? current;
}

final class PushRejected extends PushResult {
  const PushRejected(super.id, this.reason);
  final String reason;
}

class PullPage {
  const PullPage({required this.head, required this.records});

  final int head;
  final List<RemoteRecord> records;
}

/// Errors reported by the server.
sealed class SyncRemoteFailure implements Exception {
  const SyncRemoteFailure();
}

/// Network, timeout or server error: retry later.
final class RemoteUnavailable extends SyncRemoteFailure {
  const RemoteUnavailable();
}

final class NotAuthenticated extends SyncRemoteFailure {
  const NotAuthenticated();
}

final class DeviceRevoked extends SyncRemoteFailure {
  const DeviceRevoked();
}

final class DeviceUnknown extends SyncRemoteFailure {
  const DeviceUnknown();
}

final class DeviceLimitReached extends SyncRemoteFailure {
  const DeviceLimitReached();
}

final class RateLimited extends SyncRemoteFailure {
  const RateLimited();
}

final class ReauthenticationRequired extends SyncRemoteFailure {
  const ReauthenticationRequired();
}

/// Permanent refusal (invalid input): not retried.
final class RemoteRejected extends SyncRemoteFailure {
  const RemoteRejected();
}

/// Contract of the server functions in supabase/migrations. The same
/// contract is implemented by a test double for client tests, and checked
/// on the real SQL by supabase/tests.
abstract interface class SyncRemote {
  Future<void> registerDevice(
    String deviceId,
    String label, {
    String? appVersion,
  });
  Future<List<PushResult>> push(String deviceId, List<RemotePut> puts);
  Future<PullPage> pull(String deviceId, int since, {int limit = 200});
  Future<void> setRecoveryWrap(RecoveryWrap wrap);
  Future<RecoveryWrap?> getRecoveryWrap();

  /// Removes another device of the account (lost or stolen phone). Needs
  /// a recent sign-in ([ReauthenticationRequired] otherwise).
  Future<void> revokeDevice(String deviceId);
}
