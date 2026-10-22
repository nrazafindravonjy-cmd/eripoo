// Signing out with erasure and deleting the account through the real UI,
// and the notice shown after an erasure. Fictitious account only.
import 'package:eripoo/app/app.dart';
import 'package:eripoo/app/di/core_providers.dart';
import 'package:eripoo/app/router/app_router.dart';
import 'package:eripoo/app/startup/app_services.dart';
import 'package:eripoo/app/startup/local_data_eraser.dart';
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:eripoo/features/account/application/account_lifecycle.dart';
import 'package:eripoo/features/account/application/account_linker.dart';
import 'package:eripoo/features/account/presentation/account_providers.dart';
import 'package:eripoo/features/app_lock/domain/app_lock_service.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
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

/// A phone without screen lock (and no Eripoo lock): nothing more to ask.
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
    AccountBackend backend, {
    AccountLifecycle? lifecycle,
    MemorySecureKeyStore? store,
  }) async {
    setSurfaceSize(tester, phoneSize);
    final container = ProviderContainer(
      overrides: [
        secureKeyStoreProvider.overrideWithValue(
          store ?? MemorySecureKeyStore(),
        ),
        appServicesProvider.overrideWithValue(services),
        ...journeyOverrides(db: services.database),
        initialSettingsProvider.overrideWithValue(
          const AppSettings(language: AppLanguage.fr),
        ),
        accountBackendProvider.overrideWith((ref) async => backend),
        backgroundSyncEnabledProvider.overrideWithValue(false),
        deviceAuthenticatorProvider.overrideWithValue(_NoScreenLock()),
        appRestartProvider.overrideWithValue(() async => restarts++),
        if (lifecycle != null)
          accountLifecycleProvider.overrideWithValue(lifecycle),
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

  testWidgets('sign out and erase: confirmed, the phone leaves, restart', (
    tester,
  ) async {
    final services = await phone(tester);
    final backend = await linked(tester, services, 'a', create: true);
    final owner = backend.userId!;
    final erased = <ErasureReason>[];
    final lifecycle = AccountLifecycle(
      remote: backend.sync,
      media: backend.media,
      auth: backend.auth,
      eraseLocal: (reason) async => erased.add(reason),
    );
    final container = await launch(
      tester,
      services,
      backend,
      lifecycle: lifecycle,
    );
    await tap(tester, find.text('Me déconnecter et effacer ce téléphone'));
    expect(find.text('Effacer ce téléphone ?'), findsOneWidget);
    await tap(tester, find.text('Effacer'));
    await waitFor(tester, () => restarts == 1);
    expect(erased, [ErasureReason.signedOut]);
    expect(server.deviceStatus(owner, services.keys.deviceId), 'revoked');
    await close(tester, container);
  });

  testWidgets('delete the account: warned, password asked again, then '
      'deleted', (tester) async {
    final services = await phone(tester);
    final backend = await linked(tester, services, 'a', create: true);
    final owner = backend.userId!;
    final erased = <ErasureReason>[];
    final container = await launch(
      tester,
      services,
      backend,
      lifecycle: AccountLifecycle(
        remote: backend.sync,
        media: backend.media,
        auth: backend.auth,
        eraseLocal: (reason) async => erased.add(reason),
      ),
    );
    await tap(tester, find.text('Supprimer mon compte'));
    expect(find.text('Supprimer ton compte pour toujours ?'), findsOneWidget);
    expect(find.textContaining('pas même Eripoo'), findsOneWidget);
    await tap(tester, find.text('Supprimer pour toujours'));
    expect(find.text('Confirme ton mot de passe'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, password);
    await tap(tester, find.text('Confirmer'));
    await waitFor(tester, () => restarts == 1);
    expect(server.deletedAccounts, contains(owner));
    expect(erased, [ErasureReason.accountDeleted]);
    await close(tester, container);
  });

  testWidgets('with a file to keep, a PDF export is offered before the '
      'deletion', (tester) async {
    final services = await phone(tester);
    final backend = await linked(tester, services, 'a', create: true);
    await tester.runAsync(() async {
      final projects = ProjectRepository(services.database);
      final project = await projects.create('Savon du quartier');
      await projects.saveSection(
        projectId: project.id,
        sectionKey: 'problem',
        fields: {'statement': 'Le savon est loin.'},
      );
    });
    final container = await launch(
      tester,
      services,
      backend,
      lifecycle: AccountLifecycle(
        remote: backend.sync,
        media: backend.media,
        auth: backend.auth,
        eraseLocal: (_) async {},
      ),
    );
    await tap(tester, find.text('Supprimer mon compte'));
    expect(find.text('Garder une copie de ton dossier ?'), findsOneWidget);
    await tap(tester, find.text('Exporter le PDF'));
    // The usual export warning: the file leaves Eripoo's protection.
    expect(find.text('Continuer'), findsWidgets);
    await tap(tester, find.text('Annuler'));
    // Then the deletion goes on, still asking for confirmation.
    expect(find.text('Supprimer ton compte pour toujours ?'), findsOneWidget);
    await close(tester, container);
  });

  testWidgets('after an erasure, Home says why, once', (tester) async {
    final services = await phone(tester);
    final backend = await linked(tester, services, 'a', create: true);
    final store = MemorySecureKeyStore();
    await tester.runAsync(
      () => store.write(LocalDataEraser.reasonEntry, 'deviceRevoked'),
    );
    final container = await launch(tester, services, backend, store: store);
    container.read(routerProvider).go(AppRoutes.home);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('retiré de ton compte depuis un autre appareil'),
      findsOneWidget,
    );
    await tap(tester, find.text('Fermer'));
    await waitFor(
      tester,
      () => find.textContaining('retiré de ton compte').evaluate().isEmpty,
    );
    expect(
      await tester.runAsync(() => LocalDataEraser.lastReason(store)),
      isNull,
    );
    await close(tester, container);
  });
}
