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
          // AES-GCM key generated inside the Android Keystore.
          keyCipherAlgorithm: KeyCipherAlgorithm.AES_GCM_NoPadding,
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
