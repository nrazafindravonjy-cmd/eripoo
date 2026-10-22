import '../../../data/local/app_database.dart';
import '../../../security/envelopes.dart';
import '../../../security/key_manager.dart';
import '../../../sync/remote/sync_remote.dart';

/// This device already holds the data of another account. It must be
/// signed out (local data wiped) before linking a different account.
class AccountMismatch implements Exception {
  const AccountMismatch();
}

sealed class LinkResult {
  const LinkResult();
}

/// First account on this device and no key on the server yet: the guest's
/// data key becomes the account's. The recovery code must be shown to the
/// user once (and never stored).
final class NewAccountLinked extends LinkResult {
  const NewAccountLinked(this.recoveryCode);
  final String recoveryCode;
}

/// The account already has a key (another device, or a previous
/// installation): the user must unlock with the recovery code (or, later,
/// the double-QR transfer).
final class RecoveryNeeded extends LinkResult {
  const RecoveryNeeded(this.wrap);
  final RecoveryWrap wrap;
}

final class AlreadyLinked extends LinkResult {
  const AlreadyLinked();
}

/// Guest → account migration (docs/OFFLINE_SYNC.md §10, SECURITY.md §7).
///
/// Nothing local is ever deleted: guest data is already marked for
/// synchronisation and is sent at the next cycle. The local database key
/// is independent from the data key, so adopting the account's data key
/// never re-encrypts the database.
class AccountLinker {
  AccountLinker({
    required this._db,
    required this._keyManager,
    required this._remote,
  });

  final AppDatabase _db;
  final KeyManager _keyManager;
  final SyncRemote _remote;

  static const ownerKey = 'account.owner_id';

  Future<String?> linkedOwner() => _db.readValue(ownerKey);

  Future<LinkResult> link({
    required String ownerId,
    required LocalKeys localKeys,
  }) async {
    final current = await linkedOwner();
    if (current == ownerId) return const AlreadyLinked();
    if (current != null && current.isNotEmpty) throw const AccountMismatch();

    final existing = await _remote.getRecoveryWrap();
    if (existing != null) return RecoveryNeeded(existing);

    final code = _keyManager.generateRecoveryCode();
    final wrap = await _keyManager.createRecoveryWrapInBackground(
      keys: localKeys,
      ownerId: ownerId,
      code: code,
    );
    // Verify before announcing: the stored copy must open with the code.
    final check = await _keyManager.openRecoveryWrapInBackground(
      wrap: wrap,
      ownerId: ownerId,
      typedCode: code,
    );
    check.dispose();
    await _remote.setRecoveryWrap(wrap);
    await _db.writeValue(ownerKey, ownerId);
    return NewAccountLinked(code);
  }

  /// Unlocks an existing account with its recovery code. Throws
  /// [MalformedRecoveryCode] or [WrongRecoveryCode]; on success this
  /// device uses the account's data key (reload [LocalKeys] afterwards).
  Future<void> unlockWithRecoveryCode({
    required String ownerId,
    required RecoveryWrap wrap,
    required String typedCode,
  }) async {
    final current = await linkedOwner();
    if (current != null && current.isNotEmpty && current != ownerId) {
      throw const AccountMismatch();
    }
    final umk = await _keyManager.openRecoveryWrapInBackground(
      wrap: wrap,
      ownerId: ownerId,
      typedCode: typedCode,
    );
    try {
      await _keyManager.replaceDataKey(umk, wrap.umkVersion);
    } finally {
      umk.dispose();
    }
    await _db.writeValue(ownerKey, ownerId);
  }
}
