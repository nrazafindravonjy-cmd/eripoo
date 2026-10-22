import 'package:workmanager/workmanager.dart';

import '../../core/config/app_config.dart';
import '../../core/logging/app_logger.dart';
import '../../features/account/application/account_linker.dart';
import '../../features/media/data/media_store.dart';
import '../../security/key_manager.dart';
import '../../security/secure_key_store.dart';
import '../../services/backend/backend.dart';
import '../startup/app_services.dart';
import 'sync_setup.dart';

/// Entry point of the WorkManager task: runs in its own isolate, with its
/// own libsodium, database connection and Supabase client.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task == BackgroundSync.taskName) await BackgroundSync.runOnce();
    // Always "done": WorkManager's own retries would add calls on top of
    // the hourly period; the next period (or the app) tries again.
    return true;
  });
}

/// Synchronisation while the app is closed (docs/OFFLINE_SYNC.md §8): about
/// once an hour, only with a network, decided by Android (battery saving
/// may delay it). Records and, on Wi-Fi, photos.
///
/// Why WorkManager (an added dependency): changes made just before closing
/// the app would otherwise wait until the next opening; a phone used for
/// one quick note a day would almost never be saved.
abstract final class BackgroundSync {
  static const uniqueName = 'eripoo.sync';
  static const taskName = 'eripoo.sync.periodic';

  /// Plans the periodic task (kept if already planned).
  static Future<void> schedule() async {
    await Workmanager().initialize(backgroundSyncDispatcher);
    await Workmanager().registerPeriodicTask(
      uniqueName,
      taskName,
      frequency: const Duration(hours: 1),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  /// After sign-out, revocation or local erasure.
  static Future<void> cancel() => Workmanager().cancelByUniqueName(uniqueName);

  /// One cycle, if this phone is signed in to the account its data belongs
  /// to. Any failure ends quietly: nothing is lost, the app retries.
  static Future<void> runOnce({SecureKeyStore? store}) async {
    final keys = store ?? KeystoreSecureKeyStore();
    final AppServices services;
    try {
      services = await AppServices.start(keys);
    } on Object {
      return; // keys lost or database unreadable: the app shows why
    }
    SyncSetup? setup;
    DataKeys? data;
    try {
      final backend = await Backend.start(AppConfig.fromEnvironment(), keys);
      final owner = await services.database.readValue(AccountLinker.ownerKey);
      if (backend == null || owner == null || backend.userId != owner) {
        return;
      }
      data = DataKeys(services.crypto, services.keys.dataKey);
      setup = SyncSetup(
        services: services,
        backend: backend,
        ownerId: owner,
        store: keys,
        logger: AppLogger(sinks: const []),
        mediaStore: MediaStore(
          db: services.database,
          crypto: services.crypto,
          key: data.media,
          umkVersion: services.keys.dataKeyVersion,
          dir: services.mediaDirectory,
        ),
      );
      await setup.cycle();
    } on Object {
      // Retried at the next period or when the app opens.
    } finally {
      setup?.dispose();
      data?.dispose();
      await services.database.close().catchError((Object _) {});
      services.keys.dispose();
    }
  }
}
