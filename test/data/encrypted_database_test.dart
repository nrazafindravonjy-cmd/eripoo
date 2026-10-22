import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/data/local/encrypted_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

Uint8List _key(int seed) =>
    Uint8List.fromList(List.generate(32, (i) => (i * 7 + seed) & 0xff));

AppDatabase _open(File file, Uint8List key) =>
    AppDatabase(NativeDatabase(file, setup: (db) => applyDatabaseKey(db, key)));

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('eripoo_db');
    file = File('${dir.path}/eripoo.sqlite');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('uses SQLite3 Multiple Ciphers', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final version = db.select('select sqlite3mc_version() as v').single['v'];
    expect(version, startsWith('SQLite3 Multiple Ciphers'));
  });

  test('data round-trips with the right key', () async {
    final db = _open(file, _key(1));
    await db.writeValue('device_id', 'abc');
    await db.close();

    final reopened = _open(file, _key(1));
    expect(await reopened.readValue('device_id'), 'abc');
    await reopened.close();
  });

  test('the file on disk contains no plaintext and no SQLite header', () async {
    final db = _open(file, _key(1));
    await db.writeValue('probe', 'SENTINEL_PLAINTEXT_VALUE');
    await db.close();

    final raw = String.fromCharCodes(file.readAsBytesSync());
    expect(raw.contains('SENTINEL_PLAINTEXT_VALUE'), isFalse);
    expect(raw.startsWith('SQLite format 3'), isFalse);
    final wal = File('${file.path}-wal');
    if (wal.existsSync()) {
      expect(
        String.fromCharCodes(wal.readAsBytesSync()).contains('SENTINEL'),
        isFalse,
      );
    }
  });

  test('a wrong key is rejected explicitly', () async {
    final db = _open(file, _key(1));
    await db.writeValue('k', 'v');
    await db.close();

    final wrong = _open(file, _key(2));
    await expectLater(
      wrong.readValue('k'),
      throwsA(isA<DatabaseKeyMismatch>()),
    );
    await wrong.close();
  });

  test('a plain SQLite reader cannot open the file', () async {
    final db = _open(file, _key(1));
    await db.writeValue('k', 'v');
    await db.close();

    final plain = sqlite3.open(file.path);
    addTearDown(plain.close);
    expect(
      () => plain.select('select * from local_key_values'),
      throwsA(isA<SqliteException>()),
    );
  });

  test('in-memory databases cannot be keyed (tests use them unencrypted)', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    expect(
      () => applyDatabaseKey(db, _key(1)),
      throwsA(isA<SqliteException>()),
    );
  });

  test('keys must be 256 bits', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    expect(() => applyDatabaseKey(db, Uint8List(16)), throwsArgumentError);
  });

  test('writes are visible through Drift streams', () async {
    final db = _open(file, _key(3));
    addTearDown(db.close);
    final seen = <int>[];
    final sub = db
        .select(db.localKeyValues)
        .watch()
        .map((rows) => rows.length)
        .listen(seen.add);
    addTearDown(sub.cancel);
    Future<void> waitFor(int count) async {
      for (var i = 0; i < 100 && seen.length < count; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    await waitFor(1);
    await db.writeValue('a', '1');
    await waitFor(2);
    expect(seen, [0, 1]);
  });
}
