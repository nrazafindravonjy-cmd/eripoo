import 'app_lock_policy.dart';

/// Persistence of [AppLockSettings] (secure storage in the app).
abstract interface class AppLockStore {
  Future<AppLockSettings> load();
  Future<void> save(AppLockSettings settings);
}

/// Creates and checks PIN verifiers. The implementation uses Argon2id
/// (`crypto_pwhash_str`); the PIN never becomes key material.
abstract interface class PinHasher {
  Future<String> hash(String pin);
  Future<bool> verify(String verifier, String pin);
}

/// System authentication (biometrics, or the phone's own screen lock).
abstract interface class DeviceAuthenticator {
  Future<bool> canUseBiometrics();

  /// Whether the phone has its own screen lock or biometrics to prove the
  /// owner is present.
  Future<bool> isDeviceSecured();

  /// [biometricOnly] false also accepts the phone's PIN/pattern/password.
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  });
}

class PinRejected implements Exception {
  const PinRejected();
}

enum PinResetOutcome {
  /// The lock was turned off; the user can choose a new PIN.
  reset,

  /// The user cancelled or failed the system check.
  cancelled,

  /// The phone has no screen lock: another path is needed (sign in again
  /// with the recovery code).
  unavailable,
}

/// App lock logic: enabling, unlocking, attempt limits and timeout.
class AppLockService {
  AppLockService({
    required this._store,
    required this._hasher,
    required this._authenticator,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppLockStore _store;
  final PinHasher _hasher;
  final DeviceAuthenticator _authenticator;
  final DateTime Function() _clock;

  Future<AppLockSettings> settings() => _store.load();

  /// Turns the lock on (or changes the PIN).
  Future<void> enable(String pin, {bool biometric = false}) async {
    if (!AppLockPolicy.isValidPin(pin)) throw const PinRejected();
    final verifier = await _hasher.hash(pin);
    final current = await _store.load();
    await _store.save(
      current.copyWith(
        pinVerifier: () => verifier,
        biometricEnabled: biometric,
        failedAttempts: 0,
        retryAfter: () => null,
      ),
    );
  }

  /// Turns the lock off. Data is not affected.
  Future<void> disable() async {
    final current = await _store.load();
    await _store.save(
      current.copyWith(
        pinVerifier: () => null,
        biometricEnabled: false,
        failedAttempts: 0,
        retryAfter: () => null,
      ),
    );
  }

  Future<void> setTimeout(Duration timeout) async {
    if (!AppLockPolicy.timeoutChoices.contains(timeout)) {
      throw ArgumentError.value(timeout, 'timeout');
    }
    final current = await _store.load();
    await _store.save(current.copyWith(timeout: timeout));
  }

  Future<void> setBiometric(bool enabled) async {
    final current = await _store.load();
    if (!current.enabled) return;
    await _store.save(current.copyWith(biometricEnabled: enabled));
  }

  Future<UnlockResult> unlockWithPin(String pin) async {
    final current = await _store.load();
    final verifier = current.pinVerifier;
    if (verifier == null) return const Unlocked();

    final now = _clock();
    final retryAfter = current.retryAfter;
    if (retryAfter != null && now.isBefore(retryAfter)) {
      return LockedOut(retryAfter: retryAfter);
    }

    if (AppLockPolicy.isValidPin(pin) && await _hasher.verify(verifier, pin)) {
      await _store.save(
        current.copyWith(failedAttempts: 0, retryAfter: () => null),
      );
      return const Unlocked();
    }

    final failed = current.failedAttempts + 1;
    final wait = AppLockPolicy.lockoutAfter(failed);
    final next = wait == Duration.zero ? null : now.add(wait);
    await _store.save(
      current.copyWith(failedAttempts: failed, retryAfter: () => next),
    );
    return WrongPin(retryAfter: next);
  }

  /// Biometric unlock, only if the user turned it on.
  Future<bool> unlockWithBiometrics(String reason) async {
    final current = await _store.load();
    if (!current.enabled || !current.biometricEnabled) return false;
    if (!await _authenticator.canUseBiometrics()) return false;
    final ok = await _authenticator.authenticate(
      reason: reason,
      biometricOnly: true,
    );
    if (ok) {
      await _store.save(
        current.copyWith(failedAttempts: 0, retryAfter: () => null),
      );
    }
    return ok;
  }

  /// Forgotten PIN: the phone's own screen lock (or biometrics) proves the
  /// owner is present, then the app lock is turned off so a new PIN can be
  /// chosen.
  Future<PinResetOutcome> resetWithDeviceAuthentication(String reason) async {
    if (!await _authenticator.isDeviceSecured()) {
      return PinResetOutcome.unavailable;
    }
    final ok = await _authenticator.authenticate(
      reason: reason,
      biometricOnly: false,
    );
    if (!ok) return PinResetOutcome.cancelled;
    await disable();
    return PinResetOutcome.reset;
  }
}
