import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import '../../../core/time/clock.dart';
import '../../../data/local/app_database.dart';
import '../../../security/crypto_service.dart';
import '../../../security/key_manager.dart';
import '../../../sync/engine/sync_engine.dart';
import '../../../sync/remote/sync_remote.dart';
import '../../media/application/media_sync.dart';

/// A rotation is already under way on this phone (or a previous key
/// switch is not finished): one at a time.
class RotationBusy implements Exception {
  const RotationBusy();
}

/// Rotation of the data key (docs/SECURITY.md §4.10, D17): the answer to a
/// phone that had the key and can no longer be trusted (lost, stolen,
/// sold), once it has been removed from "My devices".
///
/// 1. A new key and a new recovery code are made on this phone.
/// 2. The new key is kept on this phone, then the server switches the
///    account to it, with the recovery copy sealed by the new code, in one
///    step. From then on the server refuses anything sealed with the old
///    key, and the old code no longer opens anything.
/// 3. This phone uses the new key (after a restart) and seals again,
///    with it, every record and every file the server holds; the old key
///    is erased only when nothing needs it any more.
///
/// The other phones learn at their next synchronisation that a newer key
/// exists; they get it with the new code or a transfer from this phone.
/// Their unsent changes stay on them and leave once they have it.
class KeyRotation {
  KeyRotation({
    required this._db,
    required this._crypto,
    required this._keyManager,
    required this._remote,
    this._clock = systemClock,
  });

  final AppDatabase _db;
  final CryptoService _crypto;
  final KeyManager _keyManager;
  final SyncRemote _remote;
  final Clock _clock;

  /// Set while the server copies are being sealed again (local only).
  static const stageKey = 'key_rotation.stage';
  static const _pendingSinceKey = 'key_rotation.pending_since';

  /// Longer than any request may take.
  static const _grace = Duration(minutes: 10);

  static DateTime _fromMillis(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

  Future<bool> inProgress() async => await _db.readValue(stageKey) != null;

  /// The code that will open the new key. Shown to the user before
  /// anything changes; never stored.
  String newRecoveryCode() => _keyManager.generateRecoveryCode();

  /// Steps 1 and 2. On success the app must restart to load the new key.
  ///
  /// Throws [ReauthenticationRequired] (sign in again first),
  /// [KeyVersionMismatch] (rotated meanwhile on another phone), or
  /// [RemoteUnavailable]: then the outcome is unknown — the new key stays
  /// on this phone and the next synchronisation tells whether the server
  /// switched ([settle]).
  Future<void> rotate({
    required String ownerId,
    required LocalKeys keys,
    required String code,
  }) async {
    if (await inProgress() ||
        await _keyManager.previousDataKey() != null ||
        await _keyManager.pendingDataKey() != null) {
      throw const RotationBusy();
    }
    final next = keys.dataKeyVersion + 1;
    final bytes = _crypto.randomBytes(_crypto.keyBytes);
    final key = _crypto.keyFromBytes(bytes);
    bytes.fillRange(0, bytes.length, 0);
    try {
      final newKeys = LocalKeys(
        dataKey: key,
        dataKeyVersion: next,
        databaseKey: Uint8List(0),
        deviceId: keys.deviceId,
      );
      final wrap = await _keyManager.createRecoveryWrapInBackground(
        keys: newKeys,
        ownerId: ownerId,
        code: code,
      );
      // Checked before anything changes: the copy must open with the code.
      final check = await _keyManager.openRecoveryWrapInBackground(
        wrap: wrap,
        ownerId: ownerId,
        typedCode: code,
      );
      check.dispose();

      await _db.writeValue(
        _pendingSinceKey,
        '${_clock().millisecondsSinceEpoch}',
      );
      await _keyManager.storePendingDataKey(key, next);
      final int version;
      try {
        version = await _remote.rotateDataKey(
          deviceId: keys.deviceId,
          fromVersion: keys.dataKeyVersion,
          wrap: wrap,
        );
      } on RemoteUnavailable {
        rethrow;
      } on Object {
        await _keyManager.forgetPendingDataKey();
        rethrow;
      }
      if (version != next) {
        await _keyManager.forgetPendingDataKey();
        throw const KeyVersionMismatch();
      }
      await _adopt(key, next);
    } finally {
      key.dispose();
    }
  }

  /// Uses the new key on this phone, then plans the re-encryption. Each
  /// write is idempotent: a crash in between is finished by [settle].
  Future<void> _adopt(SecureKey key, int version) async {
    await _keyManager.replaceDataKey(key, version);
    final media = await _db.select(_db.mediaItems).get();
    await _db.transaction(() async {
      await _db.writeValue(stageKey, 'reencrypting');
      await _db.deleteValue(SyncEngine.rekeyCursorKey);
      for (final row in media) {
        await _db.writeValue('${MediaSync.rekeyPrefix}${row.id}', '1');
      }
    });
    await _keyManager.forgetPendingDataKey();
  }

  /// Settles a rotation whose server answer was lost, once the account's
  /// key version is known ([serverVersion], from a synchronisation).
  /// Returns true when this phone switched to the new key (the app must
  /// restart to load it).
  Future<bool> settle({
    required int serverVersion,
    required int localVersion,
  }) async {
    final pending = await _keyManager.pendingDataKey();
    if (pending == null) return false;
    try {
      if (localVersion >= pending.version) {
        // Already in use here (crash after the switch).
        await _keyManager.forgetPendingDataKey();
        return false;
      }
      if (pending.version == serverVersion) {
        await _adopt(pending.key, pending.version);
        return true;
      }
      // The server did not switch, or another phone rotated again: this
      // key opens nothing. Kept a while in case a request is still on its
      // way (a rotation started a moment ago on this phone).
      final since = int.tryParse(await _db.readValue(_pendingSinceKey) ?? '');
      if (since == null || _clock().difference(_fromMillis(since)) > _grace) {
        await _keyManager.forgetPendingDataKey();
      }
      return false;
    } finally {
      pending.key.dispose();
    }
  }

  /// Step 3, a little at each synchronisation. Returns true when done:
  /// the previous key is then erased. Files are sent only when
  /// [mediaAllowed] (same network rule as photos). Throws
  /// [RemoteUnavailable] offline.
  Future<bool> continueRekey({
    required SyncEngine engine,
    required SyncSession session,
    required MediaSync? media,
    required bool mediaAllowed,
  }) async {
    if (!await inProgress()) return true;
    if (session.previousRecordKey != null) {
      final records = await engine.rekeyAll(session);
      if (!records.complete) return false;
      if (media != null) {
        if (!mediaAllowed) return false;
        if (await media.rekeyQueued() > 0) return false;
      }
    }
    await _keyManager.forgetPreviousDataKey();
    await _db.transaction(() async {
      await _db.deleteValue(stageKey);
      await _db.deleteValue(SyncEngine.rekeyCursorKey);
    });
    return true;
  }
}
