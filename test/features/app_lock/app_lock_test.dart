import 'package:eripoo/features/app_lock/data/app_lock_adapters.dart';
import 'package:eripoo/features/app_lock/domain/app_lock_policy.dart';
import 'package:eripoo/features/app_lock/domain/app_lock_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/memory_secure_store.dart';

/// Test doubles for the PIN hasher and the system authenticator. The real
/// Argon2id hasher is tested separately below.
class _PlainHasher implements PinHasher {
  @override
  Future<String> hash(String pin) async => 'h:$pin';

  @override
  Future<bool> verify(String verifier, String pin) async =>
      verifier == 'h:$pin';
}

class _FakeAuthenticator implements DeviceAuthenticator {
  bool biometricsAvailable = true;
  bool deviceSecured = true;
  bool answer = true;
  final calls = <bool>[];

  @override
  Future<bool> canUseBiometrics() async => biometricsAvailable;

  @override
  Future<bool> isDeviceSecured() async => deviceSecured;

  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async {
    calls.add(biometricOnly);
    return answer;
  }
}

void main() {
  group('policy', () {
    test('PIN format', () {
      expect(AppLockPolicy.isValidPin('1234'), isTrue);
      expect(AppLockPolicy.isValidPin('12345678'), isTrue);
      expect(AppLockPolicy.isValidPin('123'), isFalse);
      expect(AppLockPolicy.isValidPin('123456789'), isFalse);
      expect(AppLockPolicy.isValidPin('12a4'), isFalse);
    });

    test('waiting periods grow after the free attempts and are capped', () {
      expect(AppLockPolicy.lockoutAfter(4), Duration.zero);
      expect(AppLockPolicy.lockoutAfter(5), const Duration(seconds: 30));
      expect(AppLockPolicy.lockoutAfter(6), const Duration(minutes: 1));
      expect(AppLockPolicy.lockoutAfter(8), const Duration(minutes: 15));
      expect(AppLockPolicy.lockoutAfter(50), const Duration(hours: 1));
    });

    test('timeout on resume, and a clock going backwards locks', () {
      final t0 = DateTime(2026, 10, 6, 12);
      bool lock(Duration elapsed, Duration timeout) =>
          AppLockPolicy.shouldLockOnResume(
            backgroundedAt: t0,
            now: t0.add(elapsed),
            timeout: timeout,
          );
      expect(
        lock(const Duration(seconds: 30), const Duration(minutes: 1)),
        isFalse,
      );
      expect(
        lock(const Duration(minutes: 1), const Duration(minutes: 1)),
        isTrue,
      );
      expect(lock(Duration.zero, Duration.zero), isTrue);
      expect(
        lock(const Duration(hours: -2), const Duration(minutes: 5)),
        isTrue,
      );
    });
  });

  group('service', () {
    late MemorySecureKeyStore secure;
    late _FakeAuthenticator auth;
    late DateTime now;
    late AppLockService service;

    setUp(() {
      secure = MemorySecureKeyStore();
      auth = _FakeAuthenticator();
      now = DateTime(2026, 10, 6, 12);
      service = AppLockService(
        store: SecureAppLockStore(secure),
        hasher: _PlainHasher(),
        authenticator: auth,
        clock: () => now,
      );
    });

    test('off by default; unlocking is a no-op', () async {
      expect((await service.settings()).enabled, isFalse);
      expect(await service.unlockWithPin('0000'), isA<Unlocked>());
    });

    test('enable, unlock with the right PIN, reject a wrong one', () async {
      await service.enable('2580');
      expect((await service.settings()).enabled, isTrue);
      expect(await service.unlockWithPin('2580'), isA<Unlocked>());
      expect(await service.unlockWithPin('1111'), isA<WrongPin>());
    });

    test('invalid PINs cannot be set', () async {
      await expectLater(service.enable('12'), throwsA(isA<PinRejected>()));
      expect((await service.settings()).enabled, isFalse);
    });

    test('the PIN itself is never stored', () async {
      await service.enable('2580');
      expect(secure.values.values.join().contains('"2580"'), isFalse);
      expect((await service.settings()).pinVerifier, isNot('2580'));
    });

    test('repeated failures impose waits, even with the right PIN', () async {
      await service.enable('2580');
      for (var i = 0; i < 4; i++) {
        expect(
          (await service.unlockWithPin('0000') as WrongPin).retryAfter,
          isNull,
        );
      }
      final fifth = await service.unlockWithPin('0000') as WrongPin;
      expect(fifth.retryAfter, now.add(const Duration(seconds: 30)));
      expect(await service.unlockWithPin('2580'), isA<LockedOut>());

      now = now.add(const Duration(seconds: 31));
      expect(await service.unlockWithPin('2580'), isA<Unlocked>());
      expect((await service.settings()).failedAttempts, 0);
    });

    test('counters survive a restart (persisted)', () async {
      await service.enable('2580');
      for (var i = 0; i < 5; i++) {
        await service.unlockWithPin('0000');
      }
      final restarted = AppLockService(
        store: SecureAppLockStore(secure),
        hasher: _PlainHasher(),
        authenticator: auth,
        clock: () => now,
      );
      expect(await restarted.unlockWithPin('2580'), isA<LockedOut>());
    });

    test('biometrics only when enabled by the user and available', () async {
      await service.enable('2580');
      expect(await service.unlockWithBiometrics('r'), isFalse);
      expect(auth.calls, isEmpty);

      await service.setBiometric(true);
      expect(await service.unlockWithBiometrics('r'), isTrue);
      expect(auth.calls.single, isTrue); // biometric only

      auth.biometricsAvailable = false;
      expect(await service.unlockWithBiometrics('r'), isFalse);
    });

    test('forgotten PIN: phone authentication turns the lock off', () async {
      await service.enable('2580');
      auth.answer = false;
      expect(
        await service.resetWithDeviceAuthentication('r'),
        PinResetOutcome.cancelled,
      );
      expect((await service.settings()).enabled, isTrue);

      auth.answer = true;
      expect(
        await service.resetWithDeviceAuthentication('r'),
        PinResetOutcome.reset,
      );
      expect(auth.calls.last, isFalse); // phone PIN/pattern accepted
      expect((await service.settings()).enabled, isFalse);
    });

    test(
      'forgotten PIN without a phone screen lock needs another path',
      () async {
        await service.enable('2580');
        auth.deviceSecured = false;
        expect(
          await service.resetWithDeviceAuthentication('r'),
          PinResetOutcome.unavailable,
        );
        expect(auth.calls, isEmpty);
        expect((await service.settings()).enabled, isTrue);
      },
    );

    test('only the offered timeouts can be chosen', () async {
      await service.setTimeout(const Duration(minutes: 5));
      expect((await service.settings()).timeout, const Duration(minutes: 5));
      await expectLater(
        service.setTimeout(const Duration(seconds: 7)),
        throwsArgumentError,
      );
    });

    test('disabling keeps no verifier', () async {
      await service.enable('2580', biometric: true);
      await service.disable();
      final s = await service.settings();
      expect(s.enabled, isFalse);
      expect(s.biometricEnabled, isFalse);
    });
  });

  test('Argon2id PIN hasher (real libsodium, background isolate)', () async {
    const hasher = Argon2PinHasher();
    final verifier = await hasher.hash('2580');
    expect(verifier, startsWith(r'$argon2id$'));
    expect(verifier.contains('2580'), isFalse);
    expect(await hasher.verify(verifier, '2580'), isTrue);
    expect(await hasher.verify(verifier, '2581'), isFalse);
    expect(await hasher.hash('2580'), isNot(verifier)); // random salt
  });
}
