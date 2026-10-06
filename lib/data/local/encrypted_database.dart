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
  db.execute('pragma journal_mode = wal');
  db.execute('pragma foreign_keys = on');
}

/// Opens the app database file (in the app's private storage), encrypted
/// with [key], on a background isolate.
QueryExecutor openAppDatabaseExecutor(Uint8List key) {
  final keyCopy = Uint8List.fromList(key);
  return driftDatabase(
    name: 'eripoo',
    native: DriftNativeOptions(setup: (db) => applyDatabaseKey(db, keyCopy)),
  );
}
