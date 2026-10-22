import '../core/logging/app_logger.dart';
import 'engine/sync_engine.dart';
import 'remote/sync_remote.dart';

enum SyncRunLog implements LogEventCode { deviceRevokedLocalDataErased }

sealed class SyncRunOutcome {
  const SyncRunOutcome();
}

final class SyncRan extends SyncRunOutcome {
  const SyncRan(this.report);
  final SyncReport report;
}

/// The account session is no longer valid: the user must sign in again.
/// Local data is kept.
final class SignInNeeded extends SyncRunOutcome {
  const SignInNeeded();
}

/// This device was removed from the account. Its local data, keys and
/// session have been erased (docs/SECURITY.md §6.8); the app must restart.
final class DeviceRemoved extends SyncRunOutcome {
  const DeviceRemoved();
}

/// The data key was changed on another phone: this phone needs the new
/// one (recovery code or transfer). Local data is kept.
final class KeyOutdated extends SyncRunOutcome {
  const KeyOutdated(this.serverVersion);
  final int serverVersion;
}

/// This phone finished a key rotation whose answer had been lost: the
/// app must restart to load the new key.
final class KeyAdopted extends SyncRunOutcome {
  const KeyAdopted();
}

/// Runs a sync cycle and applies the device policies that the engine only
/// reports.
class SyncRunner {
  const SyncRunner({
    required this._engine,
    required this._eraseLocalData,
    required this._logger,
    this._settleKey,
  });

  final SyncEngine _engine;
  final Future<void> Function() _eraseLocalData;
  final AppLogger _logger;

  /// Settles a key rotation of this phone whose answer was lost, given the
  /// account's key version; true when the new key is now in use.
  final Future<bool> Function(int serverVersion)? _settleKey;

  Future<SyncRunOutcome> run(SyncSession session) async {
    try {
      final report = await _engine.runCycle(session);
      // The server is still at this phone's version.
      await _settleKey?.call(session.umkVersion);
      return SyncRan(report);
    } on DataKeyOutdated catch (e) {
      if (await _settleKey?.call(e.serverVersion) ?? false) {
        return const KeyAdopted();
      }
      return KeyOutdated(e.serverVersion);
    } on DeviceRevoked {
      // Policy: a revoked device keeps nothing. Unsynced local changes
      // are lost by design (the device is presumed lost or stolen).
      await _eraseLocalData();
      _logger.warning(SyncRunLog.deviceRevokedLocalDataErased);
      return const DeviceRemoved();
    } on NotAuthenticated {
      return const SignInNeeded();
    }
  }
}
