import 'dart:io';

import '../../data/local/app_database.dart';
import '../../security/secure_key_store.dart';

/// Why this device's local data was erased; kept after the erasure so the
/// next start can say it simply (no data, only the reason).
enum ErasureReason { userReset, deviceRevoked }

/// Erases everything Eripoo keeps on this device: the encrypted database
/// (and its WAL / shared-memory files), the encrypted media files and
/// every secure-storage entry
/// (data key, database key, device id, account session, app lock).
///
/// After this, the device cannot read old local data, cannot synchronise
/// with the old session and gets a new device id at the next start.
class LocalDataEraser {
  const LocalDataEraser({required this.store, required this.databaseFile});

  final SecureKeyStore store;
  final File databaseFile;

  static const reasonEntry = 'eripoo.erasure_reason';

  /// Where encrypted media files live: next to the database.
  static Directory mediaDirectoryOf(File databaseFile) =>
      Directory('${databaseFile.parent.path}/media');

  Future<void> eraseAll({
    required ErasureReason reason,
    AppDatabase? openDatabase,
  }) async {
    if (openDatabase != null) {
      await openDatabase.close().catchError((Object _) {});
    }
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final file = File('${databaseFile.path}$suffix');
      if (file.existsSync()) file.deleteSync();
    }
    final media = mediaDirectoryOf(databaseFile);
    if (media.existsSync()) media.deleteSync(recursive: true);
    await store.deleteAll();
    await store.write(reasonEntry, reason.name);
  }

  /// The reason of the last erasure, if any, without clearing it.
  static Future<ErasureReason?> lastReason(SecureKeyStore store) async {
    final value = await store.read(reasonEntry);
    for (final reason in ErasureReason.values) {
      if (reason.name == value) return reason;
    }
    return null;
  }

  static Future<void> acknowledge(SecureKeyStore store) =>
      store.delete(reasonEntry);
}
