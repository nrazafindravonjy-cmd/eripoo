import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../data/app_lock_adapters.dart';
import '../domain/app_lock_policy.dart';
import '../domain/app_lock_service.dart';

enum AppLockStatus {
  /// Settings not read yet: nothing is shown until we know.
  loading,

  /// The user did not turn the lock on.
  disabled,
  locked,
  unlocked,
}

final appLockServiceProvider = Provider<AppLockService>(
  (ref) => AppLockService(
    store: SecureAppLockStore(ref.watch(secureKeyStoreProvider)),
    hasher: const Argon2PinHasher(),
    authenticator: LocalAuthDeviceAuthenticator(),
  ),
);

/// Current lock state, driven by start-up and the app lifecycle.
class AppLockController extends Notifier<AppLockStatus> {
  DateTime? _backgroundedAt;

  AppLockService get _service => ref.read(appLockServiceProvider);

  @override
  AppLockStatus build() {
    _load();
    return AppLockStatus.loading;
  }

  Future<void> _load() async {
    try {
      final settings = await _service.settings();
      // A cold start always asks for the PIN when the lock is on.
      state = settings.enabled ? AppLockStatus.locked : AppLockStatus.disabled;
    } on Exception {
      // Unreadable secure storage: the data keys are unreadable too and
      // start-up reports it (LocalKeysLost). The lock is only an access
      // gate, so it does not add a second blocking screen.
      state = AppLockStatus.disabled;
    }
  }

  void onBackgrounded(DateTime now) => _backgroundedAt = now;

  Future<void> onResumed(DateTime now) async {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null || state != AppLockStatus.unlocked) return;
    final settings = await _service.settings();
    if (settings.enabled &&
        AppLockPolicy.shouldLockOnResume(
          backgroundedAt: since,
          now: now,
          timeout: settings.timeout,
        )) {
      state = AppLockStatus.locked;
    }
  }

  Future<UnlockResult> unlockWithPin(String pin) async {
    final result = await _service.unlockWithPin(pin);
    if (result is Unlocked) state = AppLockStatus.unlocked;
    return result;
  }

  Future<bool> unlockWithBiometrics(String reason) async {
    final ok = await _service.unlockWithBiometrics(reason);
    if (ok) state = AppLockStatus.unlocked;
    return ok;
  }

  Future<PinResetOutcome> resetWithDeviceAuthentication(String reason) async {
    final outcome = await _service.resetWithDeviceAuthentication(reason);
    if (outcome == PinResetOutcome.reset) state = AppLockStatus.disabled;
    return outcome;
  }

  /// After the user turns the lock on in the settings.
  Future<void> enable(String pin, {bool biometric = false}) async {
    await _service.enable(pin, biometric: biometric);
    state = AppLockStatus.unlocked;
  }

  Future<void> disable() async {
    await _service.disable();
    state = AppLockStatus.disabled;
  }
}

final appLockControllerProvider =
    NotifierProvider<AppLockController, AppLockStatus>(AppLockController.new);

/// Whether biometrics may be offered on the lock screen.
final appLockBiometricOfferedProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(appLockServiceProvider);
  final settings = await service.settings();
  return settings.biometricEnabled;
});
