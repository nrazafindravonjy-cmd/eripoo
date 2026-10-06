import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thrown when the secure storage cannot be read. Never silently ignored:
/// losing the stored keys would make local data unreadable.
class SecureStoreUnavailable implements Exception {
  const SecureStoreUnavailable();
}

/// Small string store protected by the platform keystore.
abstract interface class SecureKeyStore {
  Future<String?> read(String name);
  Future<void> write(String name, String value);
  Future<void> delete(String name);

  /// Removes every Eripoo entry (keys, session, lock settings): used only
  /// when this device's local data is erased.
  Future<void> deleteAll();
}

/// Android Keystore-backed store (docs/SECURITY.md §4.4).
class KeystoreSecureKeyStore implements SecureKeyStore {
  KeystoreSecureKeyStore()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(
          // Default ciphers on purpose: an RSA-OAEP key generated in the
          // Android Keystore wraps the AES-GCM storage key, with no user
          // authentication. The AES_GCM_NoPadding *key* cipher is the
          // plugin's biometric mode: on first launch it migrates through
          // BiometricPrompt, which crashes on Android 7-8 (API < 28, seen
          // on the CI emulator) and would ask for authentication on
          // phones with a screen lock. The Eripoo lock is separate (D4).
          keyCipherAlgorithm:
              KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
          storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
          // The library default (true) deletes *all* stored values on a
          // decryption error, which would silently destroy the keys.
          resetOnError: false,
        ),
      );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String name) async {
    try {
      return await _storage.read(key: name);
    } on Exception {
      throw const SecureStoreUnavailable();
    }
  }

  @override
  Future<void> write(String name, String value) async {
    try {
      await _storage.write(key: name, value: value);
    } on Exception {
      throw const SecureStoreUnavailable();
    }
  }

  @override
  Future<void> delete(String name) => _storage.delete(key: name);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}
