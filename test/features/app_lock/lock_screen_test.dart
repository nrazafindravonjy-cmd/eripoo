import 'package:eripoo/app/app.dart';
import 'package:eripoo/app/di/core_providers.dart';
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:eripoo/features/app_lock/data/app_lock_adapters.dart';
import 'package:eripoo/features/app_lock/domain/app_lock_service.dart';
import 'package:eripoo/features/app_lock/presentation/app_lock_controller.dart';
import 'package:eripoo/features/app_lock/presentation/lock_screen.dart';
import 'package:eripoo/features/settings/presentation/app_settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/journey_overrides.dart';
import '../../helpers/memory_secure_store.dart';
import '../../helpers/test_host.dart';

class _PlainHasher implements PinHasher {
  @override
  Future<String> hash(String pin) async => 'h:$pin';

  @override
  Future<bool> verify(String verifier, String pin) async =>
      verifier == 'h:$pin';
}

class _FakeAuthenticator implements DeviceAuthenticator {
  bool secured = true;
  bool answer = true;

  @override
  Future<bool> canUseBiometrics() async => true;

  @override
  Future<bool> isDeviceSecured() async => secured;

  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async => answer;
}

void main() {
  late MemorySecureKeyStore secure;
  late _FakeAuthenticator auth;
  late AppLockService service;

  setUp(() {
    secure = MemorySecureKeyStore();
    auth = _FakeAuthenticator();
    service = AppLockService(
      store: SecureAppLockStore(secure),
      hasher: _PlainHasher(),
      authenticator: auth,
    );
  });

  Future<ProviderContainer> pump(WidgetTester tester) async {
    setSurfaceSize(tester, phoneSize);
    final container = ProviderContainer(
      overrides: [
        secureKeyStoreProvider.overrideWithValue(secure),
        appLockServiceProvider.overrideWithValue(service),
        ...journeyOverrides(),
      ],
    );
    addTearDown(container.dispose);
    container.read(appSettingsProvider.notifier).setLanguage(AppLanguage.fr);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const EripooApp()),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> typePin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(
        find.descendant(
          of: find.byType(LockScreen),
          matching: find.text(digit),
        ),
      );
      await tester.pump();
    }
    await tester.tap(find.bySemanticsLabel('Confirmer'));
    await tester.pumpAndSettle();
  }

  testWidgets('lock off: the app opens directly', (tester) async {
    await pump(tester);
    expect(find.byType(LockScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('lock on: a cold start asks for the PIN, the right PIN opens', (
    tester,
  ) async {
    await service.enable('2580');
    final handle = tester.ensureSemantics();
    await pump(tester);
    expect(find.byType(LockScreen), findsOneWidget);
    // The app behind the lock is hidden from screen readers.
    expect(find.bySemanticsLabel('Accueil'), findsNothing);

    await typePin(tester, '2580');
    expect(find.byType(LockScreen), findsNothing);
    handle.dispose();
  });

  testWidgets('wrong PIN shows a message and stays locked', (tester) async {
    await service.enable('2580');
    await pump(tester);
    await typePin(tester, '1111');
    expect(find.text("Ce n'est pas le bon code."), findsOneWidget);
    expect(find.byType(LockScreen), findsOneWidget);
  });

  testWidgets('after too many failures the wait is shown', (tester) async {
    await service.enable('2580');
    await pump(tester);
    for (var i = 0; i < 5; i++) {
      await typePin(tester, '1111');
    }
    expect(find.textContaining("Trop d'essais"), findsOneWidget);
  });

  testWidgets('going to the background locks again after the timeout', (
    tester,
  ) async {
    await service.enable('2580');
    await service.setTimeout(Duration.zero);
    final container = await pump(tester);
    await typePin(tester, '2580');
    expect(find.byType(LockScreen), findsNothing);

    final controller = container.read(appLockControllerProvider.notifier);
    controller.onBackgrounded(DateTime.now());
    await controller.onResumed(DateTime.now());
    await tester.pumpAndSettle();
    expect(find.byType(LockScreen), findsOneWidget);
  });

  testWidgets('forgotten PIN without phone screen lock explains the way out', (
    tester,
  ) async {
    await service.enable('2580');
    auth.secured = false;
    await pump(tester);
    await tester.tap(find.text('Code PIN oublié ?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('code de récupération'), findsOneWidget);
    expect(find.byType(LockScreen), findsOneWidget);
  });

  testWidgets('forgotten PIN with phone authentication turns the lock off', (
    tester,
  ) async {
    await service.enable('2580');
    await pump(tester);
    await tester.tap(find.text('Code PIN oublié ?'));
    await tester.pumpAndSettle();
    expect(find.byType(LockScreen), findsNothing);
    expect((await service.settings()).enabled, isFalse);
  });

  for (final variant in allVariants) {
    testWidgets('lock screen layout and accessibility — $variant', (
      tester,
    ) async {
      setSurfaceSize(tester, variant.size);
      await service.enable('2580', biometric: true);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appLockServiceProvider.overrideWithValue(service)],
          child: testHost(
            const LockScreen(),
            brightness: variant.brightness,
            languageCode: variant.languageCode,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }

  for (final variant in allVariants) {
    testWidgets('lock screen at 200 % text — $variant', (tester) async {
      setSurfaceSize(tester, variant.size);
      await service.enable('2580', biometric: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appLockServiceProvider.overrideWithValue(service)],
          child: testHost(
            const LockScreen(),
            brightness: variant.brightness,
            languageCode: variant.languageCode,
            textScale: 2,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
