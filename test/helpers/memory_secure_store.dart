import 'package:eripoo/security/secure_key_store.dart';

/// In-memory stand-in for the Android Keystore-backed store (tests only).
class MemorySecureKeyStore implements SecureKeyStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String name) async => values[name];

  @override
  Future<void> write(String name, String value) async => values[name] = value;

  @override
  Future<void> delete(String name) async => values.remove(name);
}
