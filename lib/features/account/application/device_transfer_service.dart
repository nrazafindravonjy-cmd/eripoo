import '../../../data/local/app_database.dart';
import '../../../security/crypto_service.dart';
import '../../../security/device_transfer.dart';
import '../../../security/envelopes.dart';
import '../../../security/key_manager.dart';
import '../../../sync/remote/sync_remote.dart';
import 'account_linker.dart';

/// The old device is not linked to the account it is signed in to: it has
/// no account key to give.
class NotLinkedToAccount implements Exception {
  const NotLinkedToAccount();
}

/// Adding a device by double QR (docs/SECURITY.md §6.3–6.7), around the
/// pure protocol of `security/device_transfer.dart`.
///
/// On the new device, the received key is stored only after the server
/// registered this device **and** the key opened the account's existing
/// records. Every step before storing is idempotent: an interruption
/// (app closed, network lost) changes nothing that a new attempt cannot
/// redo. While the network is missing, the received key stays in memory
/// only, so the user can retry without scanning again.
class DeviceTransferService {
  DeviceTransferService({
    required this._db,
    required this._crypto,
    required this._keyManager,
    required this._remote,
  });

  final AppDatabase _db;
  final CryptoService _crypto;
  final KeyManager _keyManager;
  final SyncRemote _remote;

  /// Records looked at to check a received key (a few pages at most).
  static const _checkPages = 5;
  static const _checkPageSize = 50;

  // -------------------------------------------------------- new device (N)

  /// Step 1: the one-time key pair and QR1. Dispose it when the screen
  /// closes or the app stays in the background too long.
  TransferRequest startReceiving({
    required String ownerId,
    required String deviceId,
    required String label,
    Duration Function()? elapsed,
  }) => TransferRequest.start(
    _crypto,
    ownerId: ownerId,
    deviceId: deviceId,
    label: label,
    elapsed: elapsed,
  );

  /// Steps 7–9. Throws [AccountMismatch] (this device holds another
  /// account's data), [DeviceLimitReached], [RemoteUnavailable] (nothing
  /// stored: retry with the same [received] key),
  /// `TransferRefused(keyDoesNotMatch)`. On success this device uses the
  /// account's data key; the app must restart to load it.
  Future<void> adoptReceivedKey(
    ReceivedKey received, {
    required String ownerId,
    required String deviceId,
    required String deviceLabel,
  }) async {
    final linked = await _db.readValue(AccountLinker.ownerKey);
    if (linked != null && linked.isNotEmpty && linked != ownerId) {
      throw const AccountMismatch();
    }
    // Idempotent: the same device id is never counted twice.
    await _remote.registerDevice(deviceId, deviceLabel);
    await _checkKey(received, ownerId: ownerId, deviceId: deviceId);
    await _keyManager.replaceDataKey(received.umk, received.umkVersion);
    await _db.writeValue(AccountLinker.ownerKey, ownerId);
  }

  /// The received key must open the account's records of its version. An
  /// account with no record yet has nothing to check against: the key is
  /// accepted (docs/SECURITY.md §6.4, residual risk).
  Future<void> _checkKey(
    ReceivedKey received, {
    required String ownerId,
    required String deviceId,
  }) async {
    final keys = DataKeys(_crypto, received.umk);
    final envelopes = RecordEnvelopes(_crypto);
    var since = 0;
    var seen = 0;
    try {
      for (var page = 0; page < _checkPages; page++) {
        final result = await _remote.pull(
          deviceId,
          since,
          limit: _checkPageSize,
        );
        for (final record in result.records) {
          final payload = record.payload;
          if (payload == null) continue;
          seen++;
          if (record.umkVersion != received.umkVersion) continue;
          try {
            envelopes.open(
              envelope: payload,
              recordKey: keys.records,
              ownerId: ownerId,
              recordId: record.id,
            );
            return;
          } on DecryptionFailed {
            throw const TransferRefused(TransferFailure.keyDoesNotMatch);
          }
        }
        if (result.records.isEmpty ||
            result.records.last.version >= result.head) {
          break;
        }
        since = result.records.last.version;
      }
    } finally {
      keys.dispose();
    }
    // Records exist, but none of this key's version: not the account's
    // current key.
    if (seen > 0) {
      throw const TransferRefused(TransferFailure.keyDoesNotMatch);
    }
  }

  // -------------------------------------------------------- old device (A)

  /// Steps 2–4: QR2 for the device that showed [qr1]. Throws
  /// [NotLinkedToAccount], or [TransferRefused] (malformed QR1, another
  /// account, wrong code).
  Future<String> sealForNewDevice({
    required String qr1,
    required String typedCode,
    required String ownerId,
    required LocalKeys keys,
  }) async {
    if (await _db.readValue(AccountLinker.ownerKey) != ownerId) {
      throw const NotLinkedToAccount();
    }
    final offer = TransferOffer.parse(
      qr1,
      publicKeyBytes: _crypto.boxPublicKeyBytes,
    );
    return offer.sealKey(
      _crypto,
      ownerId: ownerId,
      typedCode: typedCode,
      umk: keys.dataKey,
      umkVersion: keys.dataKeyVersion,
      senderDeviceId: keys.deviceId,
    );
  }

  /// QR1 read by the old device, to show the new device's name before
  /// asking for the code.
  TransferOffer readOffer(String qr1) =>
      TransferOffer.parse(qr1, publicKeyBytes: _crypto.boxPublicKeyBytes);
}
