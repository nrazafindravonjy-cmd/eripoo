// Confirming the owner before a sensitive action (docs/SECURITY.md §6.2):
// the phone's lock first, the Eripoo lock PIN when the phone has none,
// with the lock screen's attempt limits.
import 'package:eripoo/features/app_lock/application/owner_check.dart';
import 'package:eripoo/features/app_lock/data/app_lock_adapters.dart';
import 'package:eripoo/features/app_lock/domain/app_lock_policy.dart';
import 'package:eripoo/features/app_lock/domain/app_lock_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/memory_secure_store.dart';

class _PlainHasher implements PinHasher {
  @override
  Future<String> hash(String pin) async => 'h:$pin';

  @override
  Future<bool> verify(String verifier, String pin) async =>
      verifier == 'h:$pin';
}

class _FakeAuthenticator implements DeviceAuthenticator {
  bool deviceSecured = true;
  final calls = <bool>[];

  @override
  Future<bool> canUseBiometrics() async => false;

  @override
  Future<bool> isDeviceSecured() async => deviceSecured;

  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async {
    calls.add(biometricOnly);
    return true;
  }
}

void main() {
  late _FakeAuthenticator auth;
  late AppLockService lock;
  late OwnerCheck check;
  late DateTime now;

  setUp(() {
    now = DateTime(2026, 10, 22, 12);
    auth = _FakeAuthenticator();
    lock = AppLockService(
      store: SecureAppLockStore(MemorySecureKeyStore()),
      hasher: _PlainHasher(),
      authenticator: auth,
      clock: () => now,
    );
    check = OwnerCheck(auth, lock);
  });

  test('the phone lock first, even with the Eripoo lock on', () async {
    await lock.enable('2468');
    expect(await check.method(), OwnerCheckMethod.device);
    expect(await check.withDevice('raison'), isTrue);
    expect(auth.calls, [false], reason: 'phone PIN or pattern accepted');
  });

  test('no phone lock: the Eripoo lock PIN instead', () async {
    auth.deviceSecured = false;
    await lock.enable('2468');
    expect(await check.method(), OwnerCheckMethod.appLockPin);
    expect(await check.withPin('1111'), isA<WrongPin>());
    expect(await check.withPin('2468'), isA<Unlocked>());
  });

  test('wrong PINs count like on the lock screen', () async {
    auth.deviceSecured = false;
    await lock.enable('2468');
    for (var i = 0; i < 5; i++) {
      await check.withPin('0000');
    }
    expect(await check.withPin('2468'), isA<LockedOut>());
    now = now.add(const Duration(hours: 2));
    expect(await check.withPin('2468'), isA<Unlocked>());
  });

  test('neither lock: nothing more can be asked', () async {
    auth.deviceSecured = false;
    expect(await check.method(), OwnerCheckMethod.none);
  });
}
