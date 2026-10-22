import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/startup/app_services.dart';
import '../../../app/startup/local_data_eraser.dart';
import '../../../app/sync/background_sync.dart';
import '../../../app/sync/sync_setup.dart';
import '../../../core/config/app_config.dart';
import '../../../data/local/app_database.dart';
import '../../../services/backend/backend.dart';
import '../../../sync/engine/sync_engine.dart';
import '../../../sync/sync_scheduler.dart';
import '../../app_lock/data/app_lock_adapters.dart';
import '../../app_lock/domain/app_lock_service.dart';
import '../../auth/domain/auth_repository.dart';
import '../../hypotheses/presentation/research_providers.dart';
import '../../quest/presentation/journey_providers.dart';
import '../application/account_lifecycle.dart';
import '../application/account_linker.dart';
import '../application/device_transfer_service.dart';

final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

/// The server of this build, or null (guest-only build). Started lazily,
/// never blocking the start-up.
final accountBackendProvider = FutureProvider<AccountBackend?>(
  (ref) => Backend.start(
    ref.watch(appConfigProvider),
    ref.watch(secureKeyStoreProvider),
  ),
);

/// Restarts the app after its keys changed (recovery, transfer) or its
/// data was erased. Set by bootstrap().
final appRestartProvider = Provider<Future<void> Function()>(
  (ref) => () async {},
);

/// The phone's own screen lock, to confirm the owner before giving the
/// data key to a new device (docs/SECURITY.md §6.2).
final deviceAuthenticatorProvider = Provider<DeviceAuthenticator>(
  (ref) => LocalAuthDeviceAuthenticator(),
);

/// Whether a WorkManager task may be planned (off in widget tests).
final backgroundSyncEnabledProvider = Provider<bool>((ref) => true);

final authUserProvider = StreamProvider<AuthUser?>((ref) async* {
  final backend = await ref.watch(accountBackendProvider.future);
  if (backend == null) {
    yield null;
    return;
  }
  yield backend.auth.currentUser;
  yield* backend.auth.userChanges();
});

/// The account this phone's data belongs to (set when linked).
final linkedOwnerProvider = FutureProvider<String?>(
  (ref) => ref.watch(appDatabaseProvider).readValue(AccountLinker.ownerKey),
);

sealed class AccountState {
  const AccountState();
}

/// No server in this build: everything stays on the phone.
final class AccountUnavailable extends AccountState {
  const AccountUnavailable();
}

/// Guest: no account yet on this phone.
final class SignedOut extends AccountState {
  const SignedOut();
}

/// Signed in, but this phone does not use the account's key yet.
final class NotLinked extends AccountState {
  const NotLinked(this.user);
  final AuthUser user;
}

final class Linked extends AccountState {
  const Linked(this.user);
  final AuthUser user;
}

/// The data here belongs to an account whose session ended.
final class SessionEnded extends AccountState {
  const SessionEnded(this.ownerId);
  final String ownerId;
}

/// Signed in to an account other than the one owning the data here.
final class OtherAccount extends AccountState {
  const OtherAccount(this.user);
  final AuthUser user;
}

final accountStateProvider = Provider<AsyncValue<AccountState>>((ref) {
  final backend = ref.watch(accountBackendProvider);
  final user = ref.watch(authUserProvider);
  final owner = ref.watch(linkedOwnerProvider);
  if (backend.isLoading || user.isLoading || owner.isLoading) {
    return const AsyncLoading();
  }
  if (backend.value == null) return const AsyncData(AccountUnavailable());
  final u = user.value;
  final o = owner.value;
  if (u == null) {
    return AsyncData(o == null ? const SignedOut() : SessionEnded(o));
  }
  if (o == null) return AsyncData(NotLinked(u));
  if (o != u.id) return AsyncData(OtherAccount(u));
  return AsyncData(Linked(u));
});

/// Null without a server.
final accountLinkerProvider = Provider<AccountLinker?>((ref) {
  final backend = ref.watch(accountBackendProvider).value;
  if (backend == null) return null;
  return AccountLinker(
    db: ref.watch(appDatabaseProvider),
    keyManager: ref.watch(appServicesProvider).keyManager,
    remote: backend.sync,
  );
});

/// Null without a server.
final accountLifecycleProvider = Provider<AccountLifecycle?>((ref) {
  final backend = ref.watch(accountBackendProvider).value;
  if (backend == null) return null;
  final services = ref.watch(appServicesProvider);
  final store = ref.watch(secureKeyStoreProvider);
  return AccountLifecycle(
    remote: backend.sync,
    media: backend.media,
    auth: backend.auth,
    eraseLocal: (reason) async => LocalDataEraser(
      store: store,
      databaseFile: await AppServices.databaseFile(),
    ).eraseAll(reason: reason, openDatabase: services.database),
  );
});

/// Null without a server.
final transferServiceProvider = Provider<DeviceTransferService?>((ref) {
  final backend = ref.watch(accountBackendProvider).value;
  if (backend == null) return null;
  final services = ref.watch(appServicesProvider);
  return DeviceTransferService(
    db: ref.watch(appDatabaseProvider),
    crypto: services.crypto,
    keyManager: services.keyManager,
    remote: backend.sync,
  );
});

/// Automatic synchronisation, while this phone is linked and signed in.
final syncControllerProvider = Provider<SyncController?>((ref) {
  final state = ref.watch(accountStateProvider).value;
  final backend = ref.watch(accountBackendProvider).value;
  if (state is! Linked || backend == null) return null;
  final db = ref.watch(appDatabaseProvider);
  final controller = SyncController(
    SyncSetup(
      services: ref.watch(appServicesProvider),
      backend: backend,
      ownerId: state.user.id,
      store: ref.watch(secureKeyStoreProvider),
      logger: ref.watch(appLoggerProvider),
      mediaStore: ref.watch(mediaStoreProvider),
    ),
    localChanges: db.tableUpdates(
      TableUpdateQuery.onAllTables([db.syncMetaEntries]),
    ),
  );
  ref.onDispose(controller.dispose);
  if (ref.watch(backgroundSyncEnabledProvider)) {
    BackgroundSync.schedule().catchError((Object _) {});
  }
  return controller;
});

/// What the user is told about the backup.
final syncStateProvider = StreamProvider<SyncState>((ref) async* {
  final controller = ref.watch(syncControllerProvider);
  if (controller == null) return;
  yield controller.scheduler.state;
  yield* controller.scheduler.states;
});

final _syncMetaTick = StreamProvider<int>((ref) {
  final db = ref.watch(appDatabaseProvider);
  var tick = 0;
  return db
      .tableUpdates(TableUpdateQuery.onAllTables([db.syncMetaEntries]))
      .map((_) => ++tick);
});

/// Local changes not yet on the server.
final pendingChangesProvider = FutureProvider<int>((ref) async {
  ref.watch(_syncMetaTick);
  final db = ref.watch(appDatabaseProvider);
  final count = db.syncMetaEntries.entityId.count(
    filter: db.syncMetaEntries.changeId.isNotNull(),
  );
  final row = await (db.selectOnly(
    db.syncMetaEntries,
  )..addColumns([count])).getSingle();
  return row.read(count) ?? 0;
});

/// The name given to this device in "My devices".
Future<void> rememberDeviceLabel(AppDatabase db, String label) =>
    db.writeValue(SyncEngine.deviceLabelKey, label);
