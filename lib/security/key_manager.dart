import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';
import 'package:uuid/uuid.dart';

import 'crypto_service.dart';
import 'envelopes.dart';
import 'recovery_code.dart';
import 'secure_key_store.dart';

/// The local database exists but its key is gone (e.g. keystore reset):
/// local data cannot be decrypted. Synced data can still be recovered with
/// the recovery code.
class LocalKeysLost implements Exception {
  const LocalKeysLost();
}

/// The typed recovery code is incomplete or contains a typing mistake.
class MalformedRecoveryCode implements Exception {
  const MalformedRecoveryCode();
}

/// The recovery code is well formed but does not open this wrap.
class WrongRecoveryCode implements Exception {
  const WrongRecoveryCode();
}

/// Keys available on this device once unlocked.
class LocalKeys {
  LocalKeys({
    required this.dataKey,
    required this.dataKeyVersion,
    required this.databaseKey,
    required this.deviceId,
  });

  /// UMK: encrypts everything that leaves the device.
  final SecureKey dataKey;
  final int dataKeyVersion;

  /// DBK: encrypts the local database file only. Independent of the UMK,
  /// so replacing the UMK (recovery) never requires re-encrypting the
  /// database.
  final Uint8List databaseKey;
  final String deviceId;

  void dispose() {
    dataKey.dispose();
    databaseKey.fillRange(0, databaseKey.length, 0);
  }
}

/// Sub-keys derived from the UMK, never stored.
class DataKeys {
  DataKeys(CryptoService crypto, SecureKey umk)
    : records = crypto.deriveSubkey(
        umk,
        EnvelopeFormat.recordKeyId,
        EnvelopeFormat.recordKeyContext,
      ),
      media = crypto.deriveSubkey(
        umk,
        EnvelopeFormat.mediaKeyId,
        EnvelopeFormat.mediaKeyContext,
      );

  final SecureKey records;
  final SecureKey media;

  void dispose() {
    records.dispose();
    media.dispose();
  }
}

/// Creates, stores and recovers keys (docs/SECURITY.md §4.3–4.4, §5).
///
/// Three separate secrets: account authentication (not handled here), the
/// data key (UMK) and the recovery code. The app-lock PIN is not a key and
/// is not handled here either.
class KeyManager {
  KeyManager(this._crypto, this._store);

  final CryptoService _crypto;
  final SecureKeyStore _store;

  static const _umkEntry = 'eripoo.umk';
  static const _dbkEntry = 'eripoo.dbk';
  static const _deviceEntry = 'eripoo.device_id';
  static const _storedFormat = 0x01;

  /// Loads the keys of this device, creating them on first launch (before
  /// any account). [databaseExists] guards against silently creating new
  /// keys for an existing encrypted database.
  Future<LocalKeys> loadOrCreate({required bool databaseExists}) async {
    final umkValue = await _store.read(_umkEntry);
    final dbkValue = await _store.read(_dbkEntry);
    final deviceId = await _store.read(_deviceEntry);

    if (umkValue != null && dbkValue != null && deviceId != null) {
      final umk = _decodeStored(umkValue, withVersion: true);
      final dbk = _decodeStored(dbkValue, withVersion: false);
      final key = _crypto.keyFromBytes(umk.bytes);
      umk.bytes.fillRange(0, umk.bytes.length, 0);
      return LocalKeys(
        dataKey: key,
        dataKeyVersion: umk.version,
        databaseKey: dbk.bytes,
        deviceId: deviceId,
      );
    }
    if (databaseExists || umkValue != null || dbkValue != null) {
      throw const LocalKeysLost();
    }

    // First launch.
    final umkBytes = _crypto.randomBytes(_crypto.keyBytes);
    final dbkBytes = _crypto.randomBytes(_crypto.keyBytes);
    final newDeviceId = const Uuid().v4();
    await _store.write(_umkEntry, _encodeStored(umkBytes, version: 1));
    await _store.write(_dbkEntry, _encodeStored(dbkBytes));
    await _store.write(_deviceEntry, newDeviceId);
    final key = _crypto.keyFromBytes(umkBytes);
    umkBytes.fillRange(0, umkBytes.length, 0);
    return LocalKeys(
      dataKey: key,
      dataKeyVersion: 1,
      databaseKey: dbkBytes,
      deviceId: newDeviceId,
    );
  }

  /// Replaces this device's data key with the account's (after recovery
  /// with the code or a device transfer). The database key is unchanged.
  Future<void> replaceDataKey(SecureKey umk, int version) async {
    final bytes = umk.extractBytes();
    await _store.write(_umkEntry, _encodeStored(bytes, version: version));
    bytes.fillRange(0, bytes.length, 0);
  }

  /// Removes every key from this device (sign-out of a shared phone,
  /// account deletion, revoked device). Irreversible for local data.
  Future<void> wipe() async {
    await _store.delete(_umkEntry);
    await _store.delete(_dbkEntry);
    await _store.delete(_deviceEntry);
  }

  /// A new recovery code: 35 uniform random digits + Damm check digit.
  String generateRecoveryCode() => RecoveryCode.fromRandomDigits([
    for (var i = 0; i < RecoveryCode.randomDigits; i++) _crypto.randomDigit(),
  ]);

  /// Encrypts the data key with a key derived from [code] (Argon2id, new
  /// random salt). The result is the only server copy of the data key.
  RecoveryWrap createRecoveryWrap({
    required LocalKeys keys,
    required String ownerId,
    required String code,
    KdfParams params = KdfParams.recoveryDefault,
  }) {
    if (!RecoveryCode.isWellFormed(code)) throw const MalformedRecoveryCode();
    final wrapId = const Uuid().v4();
    final salt = _crypto.randomBytes(_crypto.saltBytes);
    final kek = _crypto.deriveKeyFromSecret(
      RecoveryCode.secretPart(code),
      salt,
      params,
    );
    try {
      final umkBytes = keys.dataKey.extractBytes();
      final body = _crypto.encrypt(
        umkBytes,
        kek,
        ad: RecoveryWrap.associatedData(ownerId, wrapId, keys.dataKeyVersion),
      );
      umkBytes.fillRange(0, umkBytes.length, 0);
      return RecoveryWrap(
        wrapId: wrapId,
        umkVersion: keys.dataKeyVersion,
        salt: salt,
        params: params,
        wrapped: Uint8List.fromList([EnvelopeFormat.v1, ...body]),
      );
    } finally {
      kek.dispose();
    }
  }

  /// Recovers the data key from a wrap and a typed code. The check digit is
  /// verified first (instant, no key derivation); the authenticated
  /// decryption is the proof that the code is right.
  SecureKey openRecoveryWrap({
    required RecoveryWrap wrap,
    required String ownerId,
    required String typedCode,
  }) {
    final code = RecoveryCode.normalize(typedCode);
    if (code == null || !RecoveryCode.isWellFormed(code)) {
      throw const MalformedRecoveryCode();
    }
    if (wrap.wrapped.isEmpty || wrap.wrapped[0] != EnvelopeFormat.v1) {
      throw const WrongRecoveryCode();
    }
    final kek = _crypto.deriveKeyFromSecret(
      RecoveryCode.secretPart(code),
      wrap.salt,
      wrap.params,
    );
    try {
      final umkBytes = _crypto.decrypt(
        wrap.wrapped.sublist(1),
        kek,
        ad: RecoveryWrap.associatedData(ownerId, wrap.wrapId, wrap.umkVersion),
      );
      final key = _crypto.keyFromBytes(umkBytes);
      umkBytes.fillRange(0, umkBytes.length, 0);
      return key;
    } on DecryptionFailed {
      throw const WrongRecoveryCode();
    } finally {
      kek.dispose();
    }
  }

  /// [createRecoveryWrap] on a background isolate: Argon2id takes seconds
  /// on entry-level phones and must never block the UI.
  ///
  /// The isolate loads its own libsodium instance and receives only bytes
  /// (sharing native libsodium objects across isolates crashed in tests).
  /// The data key therefore transits once as a Dart byte list, zeroed
  /// after use — a best effort, as the Dart VM may keep copies.
  Future<RecoveryWrap> createRecoveryWrapInBackground({
    required LocalKeys keys,
    required String ownerId,
    required String code,
    KdfParams params = KdfParams.recoveryDefault,
  }) async {
    final umkBytes = keys.dataKey.extractBytes();
    final version = keys.dataKeyVersion;
    try {
      return await Isolate.run(
        () => _wrapInIsolate(umkBytes, version, ownerId, code, params),
      );
    } finally {
      umkBytes.fillRange(0, umkBytes.length, 0);
    }
  }

  /// [openRecoveryWrap] on a background isolate.
  Future<SecureKey> openRecoveryWrapInBackground({
    required RecoveryWrap wrap,
    required String ownerId,
    required String typedCode,
  }) async {
    final bytes = await Isolate.run(
      () => _unwrapInIsolate(wrap, ownerId, typedCode),
    );
    final key = _crypto.keyFromBytes(bytes);
    bytes.fillRange(0, bytes.length, 0);
    return key;
  }

  String _encodeStored(Uint8List key, {int? version}) => base64.encode([
    _storedFormat,
    if (version != null) ...[version >> 8, version & 0xff],
    ...key,
  ]);

  ({Uint8List bytes, int version}) _decodeStored(
    String value, {
    required bool withVersion,
  }) {
    final raw = base64.decode(value);
    final headerLength = withVersion ? 3 : 1;
    if (raw.isEmpty ||
        raw[0] != _storedFormat ||
        raw.length != headerLength + _crypto.keyBytes) {
      throw const LocalKeysLost();
    }
    return (
      bytes: Uint8List.fromList(raw.sublist(headerLength)),
      version: withVersion ? (raw[1] << 8) | raw[2] : 0,
    );
  }
}

/// Used inside background isolates, where only pure computations run.
class _NoStore implements SecureKeyStore {
  const _NoStore();

  @override
  Future<String?> read(String name) => throw UnsupportedError('isolate');

  @override
  Future<void> write(String name, String value) =>
      throw UnsupportedError('isolate');

  @override
  Future<void> delete(String name) => throw UnsupportedError('isolate');

  @override
  Future<void> deleteAll() => throw UnsupportedError('isolate');
}

// Isolate entry points: top-level so that the closures sent to the isolate
// capture only plain values.

Future<RecoveryWrap> _wrapInIsolate(
  Uint8List umkBytes,
  int version,
  String ownerId,
  String code,
  KdfParams params,
) async {
  final crypto = await CryptoService.init();
  final key = crypto.keyFromBytes(umkBytes);
  umkBytes.fillRange(0, umkBytes.length, 0);
  try {
    return KeyManager(crypto, const _NoStore()).createRecoveryWrap(
      keys: LocalKeys(
        dataKey: key,
        dataKeyVersion: version,
        databaseKey: Uint8List(0),
        deviceId: '',
      ),
      ownerId: ownerId,
      code: code,
      params: params,
    );
  } finally {
    key.dispose();
  }
}

Future<Uint8List> _unwrapInIsolate(
  RecoveryWrap wrap,
  String ownerId,
  String typedCode,
) async {
  final crypto = await CryptoService.init();
  final key = KeyManager(
    crypto,
    const _NoStore(),
  ).openRecoveryWrap(wrap: wrap, ownerId: ownerId, typedCode: typedCode);
  try {
    return key.extractBytes();
  } finally {
    key.dispose();
  }
}
