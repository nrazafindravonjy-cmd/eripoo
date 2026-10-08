import '../../../app/startup/local_data_eraser.dart';
import '../../../sync/remote/media_remote.dart';
import '../../../sync/remote/sync_remote.dart';
import '../../auth/domain/auth_repository.dart';

/// Leaving a phone and deleting the account (docs/SECURITY.md §7).
class AccountLifecycle {
  AccountLifecycle({
    required this._remote,
    required this._media,
    required this._auth,
    required this._eraseLocal,
  });

  final SyncRemote _remote;
  final MediaRemote _media;
  final AuthRepository _auth;
  final Future<void> Function(ErasureReason reason) _eraseLocal;

  /// "Sign out and erase this phone": the phone leaves the account (if the
  /// server can be reached; otherwise remove it later from another phone),
  /// the session ends, and everything Eripoo keeps here is erased. The
  /// account and its other phones are untouched. The app must restart.
  Future<void> signOutAndErase({required String deviceId}) async {
    try {
      await _remote.leaveDevice(deviceId);
    } on SyncRemoteFailure {
      // Offline or already removed: erasing this phone matters most.
    }
    try {
      await _auth.signOut();
    } on Object {
      // The local session is erased below anyway.
    }
    await _eraseLocal(ErasureReason.signedOut);
  }

  /// Deletes the account for good: the encrypted files, then everything
  /// else the server holds, then this phone's data. Needs a sign-in of
  /// less than 10 minutes: the screen asks for the password just before,
  /// so that the files are never deleted while the account would be
  /// refused ([ReauthenticationRequired]). Throws [RemoteUnavailable]
  /// offline: nothing is erased on this phone then, and it can be tried
  /// again (each step is idempotent).
  Future<void> deleteAccount() async {
    await _media.deleteAll();
    await _remote.deleteAccount();
    try {
      await _auth.signOut();
    } on Object {
      // The account no longer exists.
    }
    await _eraseLocal(ErasureReason.accountDeleted);
  }
}
