import 'package:drift/drift.dart';

import '../../../core/i18n/app_language.dart';
import '../../../data/local/app_database.dart';
import '../domain/reminder_policy.dart';

/// Shows the reminder; its text never names the mission or the project
/// (the lock screen may show it).
typedef ShowReminder = Future<void> Function(AppLanguage? language);

/// Decides from the local database whether to remind, and remembers when
/// it did. Used by the periodic background task.
class MissionReminders {
  MissionReminders(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// The setting (shared with SettingsStore) and the last reminder shown.
  static const enabledKey = 'settings.mission_reminders';
  static const lastShownKey = 'reminders.last_shown';

  /// Open missions, stored as the enum names (MissionRepository).
  static const _open = ['accepted', 'inProgress'];

  /// True when a reminder was shown.
  Future<bool> run(ShowReminder show) async {
    if (await _db.readValue(enabledKey) != 'true') return false;
    final rows = await (_db.select(
      _db.missionInstances,
    )..where((m) => m.deletedAt.isNull() & m.status.isIn(_open))).get();
    final raw = await _db.readValue(lastShownKey);
    final now = _clock();
    final due = ReminderPolicy.due(
      enabled: true,
      lastTouched: [
        for (final r in rows) DateTime.fromMillisecondsSinceEpoch(r.updatedAt),
      ],
      lastShown: raw == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(int.parse(raw)),
      now: now,
    );
    if (!due) return false;
    await show(AppLanguage.tryParse(await _db.readValue('settings.language')));
    await _db.writeValue(lastShownKey, '${now.millisecondsSinceEpoch}');
    return true;
  }
}
