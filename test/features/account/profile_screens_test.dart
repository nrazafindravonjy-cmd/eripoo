// The Profile tab through the real UI, with two simulated phones on the
// fake server: account creation with the recovery code, a second phone
// opened with that code, the double-QR transfer on both sides, "My
// devices". Fictitious accounts only (example.com).
import 'dart:async';

import 'package:eripoo/app/app.dart';
import 'package:eripoo/app/di/core_providers.dart';
import 'package:eripoo/app/router/app_router.dart';
import 'package:eripoo/app/startup/app_services.dart';
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:eripoo/design_system/design_system.dart';
import 'package:eripoo/features/account/application/account_linker.dart';
import 'package:eripoo/features/account/application/device_transfer_service.dart';
import 'package:eripoo/features/account/presentation/account_providers.dart';
import 'package:eripoo/features/app_lock/domain/app_lock_service.dart';
import 'package:eripoo/features/devices/presentation/devices_screen.dart';
import 'package:eripoo/features/devices/presentation/qr_widgets.dart';
import 'package:eripoo/features/devices/presentation/receive_key_screen.dart';
import 'package:eripoo/features/settings/domain/app_settings.dart';
import 'package:eripoo/features/settings/presentation/app_settings_controller.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:eripoo/security/device_transfer.dart';
import 'package:eripoo/services/backend/backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/fake_sync_server.dart';
import '../../helpers/journey_overrides.dart';
import '../../helpers/memory_secure_store.dart';
import '../../helpers/test_host.dart';

class _NoScreenLock implements DeviceAuthenticator {
  @override
  Future<bool> authenticate({
    required String reason,
    required bool biometricOnly,
  }) async => true;
  @override
  Future<bool> canUseBiometrics() async => false;
  @override
  Future<bool> isDeviceSecured() async => false;
}

const email = 'tiana@example.com';
const password = 'mot-de-passe-de-test';

void main() {
  late CryptoService crypto;
  late FakeSyncServer server;
  late FakeAccounts accounts;
  var restarts = 0;

  setUpAll(() async => crypto = await CryptoService.init());
  setUp(() {
    server = FakeSyncServer();
    accounts = FakeAccounts();
    restarts = 0;
  });

  Future<AppServices> phone(WidgetTester tester) async {
    final services = (await tester.runAsync(() => testServices(crypto)))!;
    addTearDown(() async {
      await services.database.close();
      services.mediaDirectory.deleteSync(recursive: true);
    });
    return services;
  }

  Future<ProviderContainer> launch(
    WidgetTester tester,
    AppServices services, {
    AccountBackend? backend,
    QrScan? scan,
  }) async {
    setSurfaceSize(tester, phoneSize);
    final container = ProviderContainer(
      overrides: [
        secureKeyStoreProvider.overrideWithValue(MemorySecureKeyStore()),
        appServicesProvider.overrideWithValue(services),
        ...journeyOverrides(db: services.database),
        initialSettingsProvider.overrideWithValue(
          const AppSettings(language: AppLanguage.fr),
        ),
        accountBackendProvider.overrideWith((ref) async => backend),
        backgroundSyncEnabledProvider.overrideWithValue(false),
        deviceAuthenticatorProvider.overrideWithValue(_NoScreenLock()),
        appRestartProvider.overrideWithValue(() async => restarts++),
        if (scan != null) qrScanProvider.overrideWithValue(scan),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const EripooApp()),
    );
    await tester.pumpAndSettle();
    container.read(routerProvider).go(AppRoutes.profile);
    await tester.pumpAndSettle();
    return container;
  }

  /// Stops the app (and its sync timers) before the test ends.
  Future<void> close(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    // Timers scheduled while closing (database streams) run out.
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Taps a button whose handler runs real work (Argon2id on an isolate),
  /// then waits for [done].
  Future<void> tapAndWait(
    WidgetTester tester,
    Finder finder,
    Future<bool> Function() done,
  ) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(finder);
      for (var i = 0; i < 300 && !await done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
  }

  /// An account created on phone A, outside the UI; returns its recovery
  /// code.
  Future<String> accountOnA(WidgetTester tester, AppServices a) async {
    final backend = FakeBackend(server, accounts, phone: 'a');
    return (await tester.runAsync(() async {
      final user = await backend.auth.signUpWithEmail(email, password);
      final result = await AccountLinker(
        db: a.database,
        keyManager: a.keyManager,
        remote: backend.sync,
      ).link(ownerId: user.id, localKeys: a.keys);
      return (result as NewAccountLinked).recoveryCode;
    }))!;
  }

  testWidgets('a build without a server says so plainly', (tester) async {
    await launch(tester, await phone(tester));
    expect(
      find.textContaining('pas encore disponible dans cette version'),
      findsOneWidget,
    );
    expect(find.text('Créer un compte'), findsNothing);
  });

  testWidgets('create an account: the recovery code is shown once and '
      'checked, then the backup is on', (tester) async {
    final services = await phone(tester);
    final backend = FakeBackend(server, accounts, phone: 'a');
    final container = await launch(tester, services, backend: backend);

    await tap(tester, find.text('Créer un compte').first);
    await tester.enterText(
      find.widgetWithText(TextField, 'Adresse e-mail'),
      email,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Mot de passe'),
      password,
    );
    await tapAndWait(
      tester,
      find.widgetWithText(EripooButton, 'Créer un compte').first,
      () async =>
          await services.database.readValue(AccountLinker.ownerKey) != null,
    );
    expect(find.text('Ton code de secours'), findsOneWidget);
    final groups = find
        .byType(Text)
        .evaluate()
        .map((e) => (e.widget as Text).data ?? '')
        .where((t) => RegExp(r'^\d{4}$').hasMatch(t))
        .toList();
    expect(groups, hasLength(9));
    await tap(tester, find.text('Je l\'ai écrit sur papier'));
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Pour vérifier, tape les 4 derniers '
        'chiffres',
      ),
      '0000' == groups.last ? '1111' : '0000',
    );
    await tap(tester, find.text('Terminé'));
    expect(
      find.text(
        'Ce ne sont pas les bons chiffres : vérifie ce que tu as '
        'écrit.',
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Pour vérifier, tape les 4 derniers '
        'chiffres',
      ),
      groups.last,
    );
    await tap(tester, find.text('Terminé'));

    expect(find.text('Connecté : $email'), findsOneWidget);
    expect(find.text('Sauvegarde'), findsOneWidget);
    expect(find.text('Mes appareils'), findsOneWidget);
    final label = await tester.runAsync(
      () => services.database.readValue('device.label'),
    );
    expect(label, startsWith('Téléphone du '));
    await close(tester, container);
  });

  testWidgets('a second phone opens the account with the recovery code', (
    tester,
  ) async {
    final a = await phone(tester);
    final code = await accountOnA(tester, a);
    final b = await phone(tester);
    await launch(tester, b, backend: FakeBackend(server, accounts, phone: 'b'));

    await tap(tester, find.text('Me connecter').first);
    await tester.enterText(
      find.widgetWithText(TextField, 'Adresse e-mail'),
      email,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Mot de passe'),
      password,
    );
    await tapAndWait(
      tester,
      find.widgetWithText(EripooButton, 'Me connecter').first,
      () async => find.text('Retrouver tes données').evaluate().isNotEmpty,
    );
    expect(
      find.text(
        'Ce compte a déjà des données. Pour les ouvrir sur ce '
        'téléphone :',
      ),
      findsOneWidget,
    );

    await tap(tester, find.text('Avec mon code de secours'));
    await tester.enterText(find.byType(TextField), '1234');
    await tapAndWait(
      tester,
      find.widgetWithText(EripooButton, 'Avec mon code de secours'),
      () async => find.textContaining('Il manque').evaluate().isNotEmpty,
    );
    expect(
      find.text('Il manque des chiffres ou l\'un d\'eux est mal tapé.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), code);
    await tapAndWait(
      tester,
      find.widgetWithText(EripooButton, 'Avec mon code de secours'),
      () async => restarts > 0,
    );
    expect(restarts, 1);
    final keys = await tester.runAsync(
      () => b.keyManager.loadOrCreate(databaseExists: true),
    );
    expect(keys!.dataKey.extractBytes(), a.keys.dataKey.extractBytes());
  });

  testWidgets('double QR, new phone side: shows QR1 and the code, reads '
      'QR2, checks the key, restarts', (tester) async {
    final a = await phone(tester);
    await accountOnA(tester, a);
    final b = await phone(tester);
    final backendB = FakeBackend(server, accounts, phone: 'b');
    final ownerId = (await tester.runAsync(
      () => backendB.auth.signInWithEmail(email, password),
    ))!.id;
    final transferA = DeviceTransferService(
      db: a.database,
      crypto: crypto,
      keyManager: a.keyManager,
      remote: FakeBackend(server, accounts, phone: 'a').sync,
    );

    late String shownCode;
    await launch(
      tester,
      b,
      backend: backendB,
      scan: (context, {required prefix}) async {
        expect(prefix, 'ERPT2:');
        // The old phone reads QR1 on this screen and the user types the
        // code shown next to it.
        final qr1 = tester.widget<QrCodeView>(find.byType(QrCodeView)).data;
        return transferA.sealForNewDevice(
          qr1: qr1,
          typedCode: shownCode,
          ownerId: ownerId,
          keys: a.keys,
        );
      },
    );
    unawaited(
      Navigator.of(tester.element(find.byType(Scaffold).first)).push(
        MaterialPageRoute<void>(
          builder: (_) => ReceiveKeyScreen(ownerId: ownerId),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recevoir la clé'), findsOneWidget);
    expect(find.byType(QrCodeView), findsOneWidget);
    expect(find.textContaining('Valable encore 4:'), findsOneWidget);
    final codeText = find
        .byType(Text)
        .evaluate()
        .map((e) => (e.widget as Text).data ?? '')
        .firstWhere((t) => RegExp(r'^\d{3} \d{3}$').hasMatch(t));
    shownCode = codeText.replaceAll(' ', '');

    await tap(tester, find.text('Scanner le code de l\'autre téléphone'));
    expect(
      find.text(
        'Clé reçue et vérifiée. Eripoo redémarre pour ouvrir tes '
        'données.',
      ),
      findsOneWidget,
    );
    await tap(tester, find.text('Redémarrer'));
    expect(restarts, 1);
    final keys = await tester.runAsync(
      () => b.keyManager.loadOrCreate(databaseExists: true),
    );
    expect(keys!.dataKey.extractBytes(), a.keys.dataKey.extractBytes());
    expect(server.deviceStatus(ownerId, b.keys.deviceId), 'active');
  });

  testWidgets('double QR, old phone side: wrong code refused, then QR2 '
      'shown 2 minutes only', (tester) async {
    final a = await phone(tester);
    await accountOnA(tester, a);
    final backendA = FakeBackend(server, accounts, phone: 'a');
    await tester.runAsync(() => backendA.auth.signInWithEmail(email, password));
    final ownerId = backendA.userId!;
    final newPhone = TransferRequest.start(
      crypto,
      ownerId: ownerId,
      deviceId: '11111111-2222-4333-8444-555555555555',
      label: 'Tablette',
    );
    addTearDown(newPhone.dispose);
    final container = await launch(
      tester,
      a,
      backend: backendA,
      scan: (context, {required prefix}) async => newPhone.qr1,
    );

    await tap(tester, find.text('Mes appareils'));
    await tap(tester, find.text('Ajouter un appareil').last);
    expect(find.textContaining('Ne scanne que ton propre'), findsOneWidget);
    await tap(tester, find.text('Scanner le code du nouveau téléphone'));
    expect(find.text('Ajouter « Tablette » ?'), findsOneWidget);

    final wrong = newPhone.code == '000000' ? '000001' : '000000';
    await tester.enterText(find.byType(TextField), wrong);
    await tap(tester, find.text('Montrer la clé'));
    expect(
      find.text('Ce n\'est pas le code affiché sur le nouveau téléphone.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byType(TextField),
      '${newPhone.code.substring(0, 3)} ${newPhone.code.substring(3)}',
    );
    await tap(tester, find.text('Montrer la clé'));
    final qr2 = tester.widget<QrCodeView>(find.byType(QrCodeView)).data;
    expect(qr2, startsWith('ERPT2:'));
    expect(newPhone.open(qr2).umkVersion, a.keys.dataKeyVersion);

    await tester.pump(const Duration(seconds: 121));
    await tester.pumpAndSettle();
    expect(find.byType(QrCodeView), findsNothing);
    expect(
      find.text('Le nouveau téléphone peut maintenant ouvrir tes données.'),
      findsOneWidget,
    );
    await close(tester, container);
  });

  testWidgets('my devices: this phone marked, another one removed', (
    tester,
  ) async {
    final a = await phone(tester);
    await accountOnA(tester, a);
    final backendA = FakeBackend(server, accounts, phone: 'a');
    await tester.runAsync(() async {
      await backendA.auth.signInWithEmail(email, password);
      await backendA.sync.registerDevice(a.keys.deviceId, 'Téléphone de Tiana');
      await server
          .clientFor(backendA.userId!, session: 'lost')
          .registerDevice('99999999-8888-4777-8666-555555555555', 'Vieux');
    });
    final container = await launch(tester, a, backend: backendA);
    await tap(tester, find.text('Mes appareils'));
    expect(find.byType(DevicesScreen), findsOneWidget);
    expect(find.text('Téléphone de Tiana'), findsOneWidget);
    expect(find.text('Ce téléphone'), findsOneWidget);

    await tap(tester, find.text('Retirer').first);
    expect(find.text('Retirer « Vieux » ?'), findsOneWidget);
    await tap(tester, find.text('Retirer').last);
    expect(find.text('Retiré'), findsOneWidget);
    expect(
      server.deviceStatus(
        backendA.userId!,
        '99999999-8888-4777-8666-555555555555',
      ),
      'revoked',
    );
    await close(tester, container);
  });
}
