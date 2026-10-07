import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../data/local/app_database.dart';
import '../../data/local/encrypted_database.dart';
import '../../security/crypto_service.dart';
import '../../security/key_manager.dart';
import '../../security/secure_key_store.dart';
import 'local_data_eraser.dart';

/// Long-lived services opened at start-up: keys, then the encrypted local
/// database. Everything works offline; no network call happens here.
class AppServices {
  AppServices({
    required this.crypto,
    required this.keyManager,
    required this.keys,
    required this.database,
    required this.mediaDirectory,
  });

  final CryptoService crypto;
  final KeyManager keyManager;
  final LocalKeys keys;
  final AppDatabase database;

  /// Encrypted media files (docs/SECURITY.md §4.7).
  final Directory mediaDirectory;

  static Future<File> databaseFile() async =>
      File('${(await getApplicationSupportDirectory()).path}/eripoo.sqlite');

  /// Throws [LocalKeysLost], [SecureStoreUnavailable] or
  /// [DatabaseKeyMismatch]; the caller shows a dedicated screen.
  /// [file] overrides the default location (tests).
  static Future<AppServices> start(SecureKeyStore store, {File? file}) async {
    final crypto = await CryptoService.init();
    final keyManager = KeyManager(crypto, store);
    final custom = file != null;
    file ??= await databaseFile();
    final keys = await keyManager.loadOrCreate(
      databaseExists: file.existsSync(),
    );
    final database = AppDatabase(
      openAppDatabaseExecutor(
        file.path,
        keys.databaseKey,
        tempDirectory: custom ? file.parent.path : null,
      ),
    );
    // Opening is lazy: run a query now so a wrong key fails at start-up,
    // not in the middle of the user's work.
    try {
      await database.customSelect('select 1').get();
    } on Object {
      await database.close().catchError((Object _) {});
      rethrow;
    }
    return AppServices(
      crypto: crypto,
      keyManager: keyManager,
      keys: keys,
      database: database,
      mediaDirectory: LocalDataEraser.mediaDirectoryOf(file),
    );
  }

  /// Erases the local database, keys and session (unreadable data, user's
  /// explicit choice). Synced data stays recoverable with the recovery code.
  static Future<void> resetLocalData(SecureKeyStore store, {File? file}) async {
    await LocalDataEraser(
      store: store,
      databaseFile: file ?? await databaseFile(),
    ).eraseAll(reason: ErasureReason.userReset);
  }
}
