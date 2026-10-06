import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

/// Authenticated decryption failed: wrong key, wrong associated data, or
/// tampered ciphertext. Carries no detail on purpose.
class DecryptionFailed implements Exception {
  const DecryptionFailed();
}

/// Argon2id cost parameters (docs/SECURITY.md §4.8).
class KdfParams {
  const KdfParams({required this.opsLimit, required this.memLimit});

  factory KdfParams.fromJson(Map<String, Object?> json) =>
      KdfParams(opsLimit: json['ops'] as int, memLimit: json['mem'] as int);

  /// Proposed production values, to be confirmed by measurement on the
  /// reference devices (DEVELOPMENT_PLAN P7/P8).
  static const recoveryDefault = KdfParams(opsLimit: 3, memLimit: 64 << 20);

  /// Floors below which parameters are never lowered.
  static const floor = KdfParams(opsLimit: 2, memLimit: 32 << 20);

  final int opsLimit;
  final int memLimit;

  Map<String, Object?> toJson() => {'ops': opsLimit, 'mem': memLimit};
}

/// The only entry point to cryptography in Eripoo: a narrow wrapper around
/// documented libsodium constructions (docs/SECURITY.md §4.2). No primitive
/// is implemented here; this class only fixes which construction is used.
///
/// Every returned byte list is a copy in Dart memory: buffers allocated by
/// libsodium must not outlive the isolate that created them (sending one
/// to another isolate crashed the test process).
class CryptoService {
  CryptoService(this.sodium);

  /// Loads libsodium (built from source by the `sodium` package hook).
  static Future<CryptoService> init() async =>
      CryptoService(await SodiumSumoInit.init());

  final SodiumSumo sodium;

  Aead get _aead => sodium.crypto.aeadXChaCha20Poly1305IETF;

  int get keyBytes => _aead.keyBytes;
  int get nonceBytes => _aead.nonceBytes;

  Uint8List randomBytes(int length) =>
      Uint8List.fromList(sodium.randombytes.buf(length));

  /// A uniformly distributed digit 0–9 (`randombytes_uniform`, no modulo
  /// bias).
  int randomDigit() => sodium.randombytes.uniform(10);

  /// A new random 256-bit key held in guarded native memory.
  SecureKey generateKey() => sodium.secureRandom(keyBytes);

  SecureKey keyFromBytes(Uint8List bytes) => sodium.secureCopy(bytes);

  /// `crypto_kdf_derive_from_key`: independent sub-keys of a master key.
  SecureKey deriveSubkey(SecureKey master, int id, String context) =>
      sodium.crypto.kdf.deriveFromKey(
        masterKey: master,
        context: context,
        subkeyId: BigInt.from(id),
        subkeyLen: keyBytes,
      );

  /// XChaCha20-Poly1305 with a random 192-bit nonce. Returns
  /// `nonce || ciphertext || tag`.
  Uint8List encrypt(Uint8List message, SecureKey key, {Uint8List? ad}) {
    final nonce = randomBytes(nonceBytes);
    final cipher = _aead.encrypt(
      message: message,
      nonce: nonce,
      key: key,
      additionalData: ad,
    );
    return Uint8List.fromList([...nonce, ...cipher]);
  }

  /// Inverse of [encrypt]. Throws [DecryptionFailed] on any failure.
  Uint8List decrypt(Uint8List sealed, SecureKey key, {Uint8List? ad}) {
    if (sealed.length < nonceBytes + _aead.aBytes) {
      throw const DecryptionFailed();
    }
    try {
      return Uint8List.fromList(
        _aead.decrypt(
          cipherText: sealed.sublist(nonceBytes),
          nonce: sealed.sublist(0, nonceBytes),
          key: key,
          additionalData: ad,
        ),
      );
    } on SodiumException {
      throw const DecryptionFailed();
    }
  }

  /// Argon2id v1.3 (`crypto_pwhash`) → 256-bit key.
  SecureKey deriveKeyFromSecret(
    String secret,
    Uint8List salt,
    KdfParams params,
  ) => sodium.crypto.pwhash.callStr(
    outLen: keyBytes,
    password: secret,
    salt: salt,
    opsLimit: params.opsLimit,
    memLimit: params.memLimit,
    alg: CryptoPwhashAlgorithm.argon2id13,
  );

  int get saltBytes => sodium.crypto.pwhash.saltBytes;

  /// `crypto_pwhash_str` (Argon2id): self-describing verifier string, used
  /// only for the app-lock PIN, never for key material.
  String hashForVerification(String secret, KdfParams params) =>
      sodium.crypto.pwhash.str(
        password: secret,
        opsLimit: params.opsLimit,
        memLimit: params.memLimit,
      );

  bool verifyHash(String hash, String secret) =>
      sodium.crypto.pwhash.strVerify(passwordHash: hash, password: secret);

  /// `sodium_pad` / `sodium_unpad` to hide exact lengths.
  Uint8List pad(Uint8List data, int blockSize) =>
      Uint8List.fromList(sodium.pad(data, blockSize));

  Uint8List unpad(Uint8List data, int blockSize) {
    try {
      return Uint8List.fromList(sodium.unpad(data, blockSize));
    } on SodiumException {
      throw const DecryptionFailed();
    }
  }

  /// BLAKE2b (`crypto_generichash`).
  Uint8List hash(Uint8List message, {int length = 32}) => Uint8List.fromList(
    sodium.crypto.genericHash.call(message: message, outLen: length),
  );
}
