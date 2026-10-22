// Optional mission reminders (CLAUDE.md §46): off by default, at most one
// a day, daytime only, only for a mission left waiting, never naming the
// mission or the project. Fictitious data.
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/reminders/application/mission_reminders.dart';
import 'package:eripoo/features/reminders/domain/reminder_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

void main() {
  final noon = DateTime(2026, 10, 22, 12);
  final threeDaysAgo = noon.subtract(const Duration(days: 3));

  group('policy', () {
    bool due({
      bool enabled = true,
      List<DateTime>? touched,
      DateTime? lastShown,
      DateTime? now,
    }) => ReminderPolicy.due(
      enabled: enabled,
      lastTouched: touched ?? [threeDaysAgo],
      lastShown: lastShown,
      now: now ?? noon,
    );

    test('a mission waiting two days, in the daytime: remind', () {
      expect(due(), isTrue);
    });
    test('off, or nothing waiting long enough: no reminder', () {
      expect(due(enabled: false), isFalse);
      expect(due(touched: []), isFalse);
      expect(due(touched: [noon.subtract(const Duration(hours: 30))]), isFalse);
    });
    test('never in the evening or at night', () {
      expect(due(now: DateTime(2026, 10, 22, 8, 59)), isFalse);
      expect(due(now: DateTime(2026, 10, 22, 20)), isFalse);
      expect(due(now: DateTime(2026, 10, 22, 19, 59)), isTrue);
    });
    test('at most one a day', () {
      expect(due(lastShown: noon.subtract(const Duration(hours: 5))), isFalse);
      expect(due(lastShown: noon.subtract(const Duration(hours: 21))), isTrue);
    });
  });

  group('background check', () {
    late AppDatabase db;
    setUp(() => db = memoryDatabase());
    tearDown(() => db.close());

    Future<void> mission(String status, DateTime updated) => db
        .into(db.missionInstances)
        .insert(
          MissionInstancesCompanion.insert(
            id: 'm-$status',
            templateId: 'm.observe_problem',
            status: status,
            createdAt: updated.millisecondsSinceEpoch,
            updatedAt: updated.millisecondsSinceEpoch,
          ),
        );

    test('shown once, in the chosen language, only when turned on', () async {
      final shown = <AppLanguage?>[];
      Future<void> show(AppLanguage? l) async => shown.add(l);
      final reminders = MissionReminders(db, clock: () => noon);
      await mission('accepted', threeDaysAgo);

      expect(await reminders.run(show), isFalse, reason: 'off by default');
      await db.writeValue(MissionReminders.enabledKey, 'true');
      await db.writeValue('settings.language', 'fr');
      expect(await reminders.run(show), isTrue);
      expect(shown, [AppLanguage.fr]);
      expect(await reminders.run(show), isFalse, reason: 'once a day');
    });

    test('finished or abandoned missions never remind', () async {
      await db.writeValue(MissionReminders.enabledKey, 'true');
      await mission('completed', threeDaysAgo);
      await mission('abandoned', threeDaysAgo);
      final reminders = MissionReminders(db, clock: () => noon);
      expect(await reminders.run((_) async {}), isFalse);
    });
  });
}
