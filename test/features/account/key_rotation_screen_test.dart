// Changing the data key through the real UI (docs/SECURITY.md §4.10): the
// account password asked again, the new code shown and checked, the
// server switched, the app restarted; and another phone told to use the
// new code. Fictitious account only (example.com).
import 'package:eripoo/app/app.dart';
import 'package:eripoo/app/di/core_providers.dart';
import 'package:eripoo/app/router/app_router.dart';
import 'package:eripoo/app/startup/app_services.dart';
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:eripoo/design_system/design_system.dart';
import 'package:eripoo/features/account/application/account_linker.dart';
import 'package:eripoo/features/account/application/key_rotation.dart';
import 'package:eripoo/features/account/presentation/account_providers.dart';
import 'package:eripoo/features/settings/domain/app_settings.dart';
import 'package:eripoo/features/settings/presentation/app_settings_controller.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:eripoo/services/backend/backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_backend.dart';
import '../../helpers/fake_sync_server.dart';
import '../../helpers/journey_overrides.dart';
import '../../helpers/memory_secure_store.dart';
import '../../helpers/test_host.dart';

const email = 'tiana@example.com';
const password = 'mot-de-passe-de-test';

void main() {
  late CryptoService crypto;
  late FakeSyncServer server;
  late FakeAccounts accounts;
  var restarts = 0;

  setUpAll(() async => crypto = await CryptoService.init());

  // The network, as connectivity_plus reports it: Wi-Fi.
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => ['wifi'],
    );
    messenger.setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
  });
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

  /// A phone linked to the account and signed in.
  Future<FakeBackend> linked(
    WidgetTester tester,
    AppServices services,
    String name, {
    bool create = false,
  }) async {
    final backend = FakeBackend(server, accounts, phone: name);
    await tester.runAsync(() async {
      final user = create
          ? await backend.auth.signUpWithEmail(email, password)
          : await backend.auth.signInWithEmail(email, password);
      await services.database.writeValue(AccountLinker.ownerKey, user.id);
      await backend.sync.registerDevice(services.keys.deviceId, name);
      if (create) {
        await AccountLinker(
          db: services.database,
          keyManager: services.keyManager,
          remote: backend.sync,
        ).link(ownerId: user.id, localKeys: services.keys);
      }
    });
    return backend;
  }

  Future<ProviderContainer> launch(
    WidgetTester tester,
    AppServices services,
    AccountBackend backend,
  ) async {
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
        appRestartProvider.overrideWithValue(() async => restarts++),
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

  Future<void> close(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
  }

  /// Lets real work (database, Argon2id isolates) run until [done].
  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 300 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(done(), isTrue);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('change the key: password, new code checked, server '
      'switched, restart', (tester) async {
    final services = await phone(tester);
    final backend = await linked(tester, services, 'a', create: true);
    final container = await launch(tester, services, backend);
    await waitFor(
      tester,
      () => find.text('Tout est sauvegardé.').evaluate().isNotEmpty,
    );

    await tap(tester, find.text('Changer la clé de mes données'));
    expect(find.textContaining('perdu, volé ou donné'), findsOneWidget);
    await waitFor(
      tester,
      () =>
          tester
              .widget<EripooButton>(
                find.widgetWithText(EripooButton, 'Créer une nouvelle clé'),
              )
              .onPressed !=
          null,
    );
    await tap(tester, find.text('Créer une nouvelle clé'));
    expect(find.text('Changer la clé maintenant ?'), findsOneWidget);
    await tap(tester, find.text('Créer une nouvelle clé').last);

    // The password, asked again (recent sign-in required).
    expect(find.text('Confirme ton mot de passe'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, password);
    await tap(tester, find.text('Confirmer'));
    await waitFor(
      tester,
      () => find.text('Ton code de secours').evaluate().isNotEmpty,
    );
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
        'Pour vérifier, tape les 4 derniers chiffres',
      ),
      groups.last,
    );
    await tap(tester, find.text('Terminé'));
    await waitFor(tester, () => restarts == 1);
    expect(server.keyVersionOf(backend.userId!), 2);
    expect(
      await tester.runAsync(
        () => services.database.readValue(KeyRotation.stageKey),
      ),
      'reencrypting',
    );
    await close(tester, container);
  });

  testWidgets('another phone is told to use the new code, and keeps its '
      'data meanwhile', (tester) async {
    final a = await phone(tester);
    final backendA = await linked(tester, a, 'a', create: true);
    final b = await phone(tester);
    final backendB = await linked(tester, b, 'b');
    // Rotated on A, outside the UI.
    await tester.runAsync(
      () =>
          KeyRotation(
            db: a.database,
            crypto: a.crypto,
            keyManager: a.keyManager,
            remote: backendA.sync,
          ).rotate(
            ownerId: backendA.userId!,
            keys: a.keys,
            code: a.keyManager.generateRecoveryCode(),
          ),
    );

    final container = await launch(tester, b, backendB);
    await waitFor(
      tester,
      () => find
          .textContaining('changée sur un autre téléphone')
          .evaluate()
          .isNotEmpty,
    );
    expect(find.text('Ouvrir avec le nouveau code'), findsOneWidget);
    await tap(tester, find.text('Ouvrir avec le nouveau code'));
    await waitFor(
      tester,
      () => find.text('Avec mon code de secours').evaluate().isNotEmpty,
    );
    await close(tester, container);
  });
}
