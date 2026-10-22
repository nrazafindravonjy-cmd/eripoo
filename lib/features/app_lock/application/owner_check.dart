import '../domain/app_lock_policy.dart';
import '../domain/app_lock_service.dart';

/// How the owner proves they are holding the phone before a sensitive
/// action (recovery, transfer, key rotation, removing a device, deleting
/// the account; docs/SECURITY.md §6.2).
enum OwnerCheckMethod {
  /// The phone's own screen lock or biometrics.
  device,

  /// No screen lock on the phone: the Eripoo lock PIN instead.
  appLockPin,

  /// Neither: nothing more can be asked on this phone.
  none,
}

class OwnerCheck {
  OwnerCheck(this._authenticator, this._lock);

  final DeviceAuthenticator _authenticator;
  final AppLockService _lock;

  /// The phone's lock first; the Eripoo lock only when the phone has none.
  Future<OwnerCheckMethod> method() async {
    if (await _authenticator.isDeviceSecured()) return OwnerCheckMethod.device;
    if ((await _lock.settings()).enabled) return OwnerCheckMethod.appLockPin;
    return OwnerCheckMethod.none;
  }

  Future<bool> withDevice(String reason) =>
      _authenticator.authenticate(reason: reason, biometricOnly: false);

  /// Same attempt limits and waits as the lock screen.
  Future<UnlockResult> withPin(String pin) => _lock.unlockWithPin(pin);
}
