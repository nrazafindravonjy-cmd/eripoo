// Opt-in anonymous statistics (decision D7): nothing counted or sent
// without consent, "app opened" once a day, totals capped as the server
// expects, kept when sending fails, forgotten when turned off.
import 'dart:io';

import 'package:eripoo/core/config/app_version.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/usage/application/usage_counter.dart';
import 'package:eripoo/features/usage/domain/usage_event.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late DateTime now;
  late UsageCounter counter;
  late List<Map<String, int>> sent;
  Future<void> sink(Map<String, int> totals) async => sent.add(totals);

  setUp(() {
    db = memoryDatabase();
    now = DateTime(2026, 10, 22, 10);
    counter = UsageCounter(db, clock: () => now);
    sent = [];
  });
  tearDown(() => db.close());

  test('without consent nothing is counted nor sent', () async {
    await counter.record(UsageEvent.questCompleted);
    await counter.flush(sink);
    expect(sent, isEmpty);
  });

  test('totals only, "app opened" once a day, then cleared', () async {
    await db.writeValue(UsageCounter.enabledKey, 'true');
    await counter.record(UsageEvent.appOpened);
    await counter.record(UsageEvent.appOpened);
    await counter.record(UsageEvent.questCompleted);
    await counter.record(UsageEvent.questCompleted);
    await counter.flush(sink);
    expect(sent, [
      {'app_opened': 1, 'quest_completed': 2},
    ]);
    await counter.flush(sink);
    expect(sent, hasLength(1), reason: 'nothing left to send');
    now = now.add(const Duration(days: 1));
    await counter.record(UsageEvent.appOpened);
    await counter.flush(sink);
    expect(sent.last, {'app_opened': 1});
  });

  test('kept when sending fails, capped at the server limit', () async {
    await db.writeValue(UsageCounter.enabledKey, 'true');
    for (var i = 0; i < 150; i++) {
      await counter.record(UsageEvent.pdfExported);
    }
    await expectLater(
      counter.flush((_) async => throw const SocketException('offline')),
      throwsA(isA<SocketException>()),
    );
    await counter.flush(sink);
    expect(sent.single, {'pdf_exported': UsageCounter.maxPerEvent});
  });

  test('turned off: what was not sent is forgotten', () async {
    await db.writeValue(UsageCounter.enabledKey, 'true');
    await counter.record(UsageEvent.missionCompleted);
    await counter.forgetPending();
    await counter.flush(sink);
    expect(sent, isEmpty);
  });

  test('the events match the server list and the version matches pubspec', () {
    final migration = File('supabase/migrations/20261022000001_usage_stats.sql')
        .readAsStringSync();
    for (final e in UsageEvent.values) {
      expect(migration, contains("'${e.token}'"), reason: e.name);
    }
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('\nversion: $appVersion\n'));
  });
}
