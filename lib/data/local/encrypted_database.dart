import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:sqlite3/common.dart';

/// Thrown when the local database cannot be decrypted with the given key
/// (wrong key, or a file that is not an Eripoo database).
class DatabaseKeyMismatch implements Exception {
  const DatabaseKeyMismatch();
}

/// Applies the database key to a freshly opened SQLite3MultipleCiphers
/// connection, then checks that the key works.
///
/// The key is the 256-bit random DBK (docs/SECURITY.md §4.3). It is passed
/// with sqlite3mc's documented `raw:` prefix, which bypasses PBKDF2: the
/// key is already random, so key stretching would only slow down opening
/// on entry-level phones without adding security.
void applyDatabaseKey(CommonDatabase db, Uint8List key) {
  if (key.length != 32) {
    throw ArgumentError.value(key.length, 'key.length', 'must be 32 bytes');
  }
  final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  db.execute("pragma cipher = 'chacha20'");
  db.execute("pragma key = 'raw:$hex'");
  try {
    // Reading the schema fails if the key is wrong.
    db.select('select count(*) from sqlite_master');
  } on SqliteException {
    throw const DatabaseKeyMismatch();
  }
  // Temporary tables and sort spills stay in memory: whether sqlite3mc
  // encrypts temporary files is not verified, so none are written.
  db.execute('pragma temp_store = memory');
  db.execute('pragma journal_mode = wal');
  db.execute('pragma foreign_keys = on');
}

/// Opens the database file at [path] (app private storage), encrypted with
/// [key], on a background isolate. [tempDirectory] overrides the platform
/// temporary directory (tests, where no platform plugin exists).
QueryExecutor openAppDatabaseExecutor(
  String path,
  Uint8List key, {
  String? tempDirectory,
}) {
  final keyCopy = Uint8List.fromList(key);
  return driftDatabase(
    name: 'eripoo',
    native: DriftNativeOptions(
      databasePath: () async => path,
      tempDirectoryPath: tempDirectory == null
          ? null
          : () async => tempDirectory,
      setup: (db) => applyDatabaseKey(db, keyCopy),
    ),
  );
}
