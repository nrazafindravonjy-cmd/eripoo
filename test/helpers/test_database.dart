import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:eripoo/data/local/app_database.dart';

/// In-memory database for business tests. Unencrypted on purpose:
/// sqlite3mc cannot key in-memory databases; encryption is tested on files
/// in test/data/encrypted_database_test.dart.
AppDatabase memoryDatabase() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// A controllable clock.
class TestClock {
  DateTime now = DateTime.utc(2026, 10, 6, 12);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}
