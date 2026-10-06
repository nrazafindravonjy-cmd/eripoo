import 'dart:io';

import 'package:eripoo/app/startup/app_services.dart';
import 'package:eripoo/app/startup/startup_failure_app.dart';
import 'package:eripoo/security/key_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_secure_store.dart';

const _keysLostTitle = 'Your data cannot be opened on this phone';
const _reset = 'Start again on this phone';
const _confirmTitle = 'Erase the data on this phone?';

void main() {
  group('AppServices.start', () {
    late Directory dir;
    late File file;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('eripoo_start');
      file = File('${dir.path}/eripoo.sqlite');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('first start creates keys and an encrypted database', () async {
      final store = MemorySecureKeyStore();
      final services = await AppServices.start(store, file: file);
      await services.database.writeValue('probe', 'kept');
      await services.database.close();

      expect(file.existsSync(), isTrue);
      expect(store.values.keys, containsAll(['eripoo.umk', 'eripoo.dbk']));
      // Never readable as plain SQLite: no SQLite header in the file.
      final header = String.fromCharCodes(file.readAsBytesSync().take(15));
      expect(header, isNot('SQLite format 3'));

      final again = await AppServices.start(store, file: file);
      addTearDown(again.database.close);
      expect(await again.database.readValue('probe'), 'kept');
      final pragmas = await again.database
          .customSelect('pragma temp_store')
          .getSingle();
      expect(pragmas.data.values.single, 2, reason: 'temp_store = memory');
    });

    test('database present but keys gone: LocalKeysLost, no silent '
        'recreation', () async {
      final store = MemorySecureKeyStore();
      final services = await AppServices.start(store, file: file);
      await services.database.close();

      final emptied = MemorySecureKeyStore();
      await expectLater(
        AppServices.start(emptied, file: file),
        throwsA(isA<LocalKeysLost>()),
      );
      expect(emptied.values, isEmpty);
      expect(file.existsSync(), isTrue);
    });

    test('wrong database key: start fails, the file is kept', () async {
      final store = MemorySecureKeyStore();
      final services = await AppServices.start(store, file: file);
      await services.database.writeValue('probe', 'kept');
      await services.database.close();
      final before = file.readAsBytesSync();

      final other = MemorySecureKeyStore();
      final otherDir = Directory.systemTemp.createTempSync('eripoo_other');
      addTearDown(() => otherDir.deleteSync(recursive: true));
      final otherServices = await AppServices.start(
        other,
        file: File('${otherDir.path}/eripoo.sqlite'),
      );
      await otherServices.database.close();
      store.values['eripoo.dbk'] = other.values['eripoo.dbk']!;

      await expectLater(
        AppServices.start(store, file: file),
        throwsA(anything),
      );
      expect(file.readAsBytesSync(), before);
    });

    test('reset erases the database and keys, then a fresh start '
        'works', () async {
      final store = MemorySecureKeyStore();
      final services = await AppServices.start(store, file: file);
      await services.database.writeValue('probe', 'old');
      await services.database.close();
      store.values.remove('eripoo.dbk');

      await AppServices.resetLocalData(store, file: file);
      expect(file.existsSync(), isFalse);
      expect(store.values, isEmpty);

      final fresh = await AppServices.start(store, file: file);
      addTearDown(fresh.database.close);
      expect(await fresh.database.readValue('probe'), isNull);
    });
  });

  group('StartupFailureApp', () {
    testWidgets('lost keys: explains and resets only after '
        'confirmation', (tester) async {
      var resets = 0;
      await tester.pumpWidget(
        StartupFailureApp(
          error: const LocalKeysLost(),
          onReset: () async => resets++,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_keysLostTitle), findsOneWidget);
      await tester.tap(find.text(_reset));
      await tester.pumpAndSettle();
      expect(find.text(_confirmTitle), findsOneWidget);
      expect(resets, 0, reason: 'a dialog must ask first');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(resets, 0);

      await tester.tap(find.text(_reset));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_reset).last);
      await tester.pumpAndSettle();
      expect(resets, 1);
    });

    testWidgets('other failures offer no destructive action', (tester) async {
      await tester.pumpWidget(
        StartupFailureApp(error: StateError('x'), onReset: () async {}),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ButtonStyleButton), findsNothing);
    });
  });
}
