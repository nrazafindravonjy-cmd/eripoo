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

/// Runs a sync cycle and applies the device policies that the engine only
/// reports.
class SyncRunner {
  const SyncRunner({
    required this._engine,
    required this._eraseLocalData,
    required this._logger,
  });

  final SyncEngine _engine;
  final Future<void> Function() _eraseLocalData;
  final AppLogger _logger;

  Future<SyncRunOutcome> run(SyncSession session) async {
    try {
      return SyncRan(await _engine.runCycle(session));
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
