import 'dart:convert';
import 'dart:isolate';

import 'package:local_auth/local_auth.dart';

import '../../../security/crypto_service.dart';
import '../../../security/secure_key_store.dart';
import '../domain/app_lock_policy.dart';
import '../domain/app_lock_service.dart';

/// Lock settings in the Keystore-protected store.
class SecureAppLockStore implements AppLockStore {
  SecureAppLockStore(this._store);

  final SecureKeyStore _store;
  static const _entry = 'eripoo.applock';

  @override
  Future<AppLockSettings> load() async {
    final raw = await _store.read(_entry);
    if (raw == null) return const AppLockSettings();
    return AppLockSettings.fromJson(jsonDecode(raw) as Map<String, Object?>);
  }

  @override
  Future<void> save(AppLockSettings settings) =>
      _store.write(_entry, jsonEncode(settings.toJson()));
}

/// Argon2id PIN verifier (`crypto_pwhash_str`), computed on a background
/// isolate. Moderate cost: the lock is an access gate, not the data
/// protection, and must stay quick on entry-level phones.
class Argon2PinHasher implements PinHasher {
  const Argon2PinHasher({
    this.params = const KdfParams(opsLimit: 2, memLimit: 32 << 20),
  });

  final KdfParams params;

  @override
  Future<String> hash(String pin) {
    final params = this.params;
    return Isolate.run(() async {
      final crypto = await CryptoService.init();
      return crypto.hashForVerification(pin, params);
    });
  }

  @override
  Future<bool> verify(String verifier, String pin) => Isolate.run(() async {
    final crypto = await CryptoService.init();
    return crypto.verifyHash(verifier, pin);
  });
}

/// Biometrics and device credential through `local_auth`.
///
/// ⚠️ NOT VERIFIED on a device: requires `FlutterFragmentActivity`, the
/// `USE_BIOMETRIC` permission and an AppCompat launch theme (configured in
/// `android/`, checked only by the CI build).
class LocalAuthDeviceAuthenticator implements DeviceAuthenticator {
  LocalAuthDeviceAuthenticator([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> canUseBiometrics() async {
    try {
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on Exception {
      return false;
    }
  }

  @override
  Future<bool> isDeviceSecured() async {
    try {
      return await _auth.isDeviceSupported();
    } on Exception {
      return false;
    }
  }

  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: biometricOnly,
      );
    } on Exception {
      return false;
    }
  }
}
