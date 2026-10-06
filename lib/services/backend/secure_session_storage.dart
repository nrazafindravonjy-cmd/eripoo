import 'package:supabase_flutter/supabase_flutter.dart';

import '../../security/secure_key_store.dart';

/// Keeps the Supabase session in the Keystore-backed store instead of
/// SharedPreferences (the library default, docs/SECURITY.md §10).
class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage(this._store);

  final SecureKeyStore _store;
  static const _entry = 'eripoo.session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => (await _store.read(_entry)) != null;

  @override
  Future<String?> accessToken() => _store.read(_entry);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _store.write(_entry, persistSessionString);

  @override
  Future<void> removePersistedSession() => _store.delete(_entry);
}

/// Same for the short-lived PKCE verifier of redirect-based sign-ins.
class SecurePkceStorage extends GotrueAsyncStorage {
  const SecurePkceStorage(this._store);

  final SecureKeyStore _store;
  static String _name(String key) => 'eripoo.pkce.$key';

  @override
  Future<String?> getItem({required String key}) => _store.read(_name(key));

  @override
  Future<void> setItem({required String key, required String value}) =>
      _store.write(_name(key), value);

  @override
  Future<void> removeItem({required String key}) => _store.delete(_name(key));
}
