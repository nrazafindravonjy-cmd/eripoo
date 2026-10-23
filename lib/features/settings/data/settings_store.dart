import '../../../core/i18n/app_language.dart';
import '../../../data/local/app_database.dart';
import '../../reminders/application/mission_reminders.dart';
import '../../usage/application/usage_counter.dart';
import '../domain/app_settings.dart';

/// Display preferences kept in the local database (technical key/values,
/// not synchronised: a preference of this phone).
class SettingsStore {
  SettingsStore(this._db);

  final AppDatabase _db;

  static const _language = 'settings.language';
  static const _reducedMotion = 'settings.reduced_motion';
  static const _celebrations = 'settings.celebrations';
  static const _missionReminders = MissionReminders.enabledKey;
  static const _usageStats = UsageCounter.enabledKey;

  Future<AppSettings> load() async {
    return AppSettings(
      language: AppLanguage.tryParse(await _db.readValue(_language)),
      reducedMotion: await _db.readValue(_reducedMotion) == 'true',
      celebrations: await _db.readValue(_celebrations) != 'false',
      missionReminders: await _db.readValue(_missionReminders) == 'true',
      usageStats: await _db.readValue(_usageStats) == 'true',
    );
  }

  Future<void> save(AppSettings settings) async {
    final language = settings.language;
    if (language != null) await _db.writeValue(_language, language.name);
    await _db.writeValue(_reducedMotion, '${settings.reducedMotion}');
    await _db.writeValue(_celebrations, '${settings.celebrations}');
    await _db.writeValue(_missionReminders, '${settings.missionReminders}');
    await _db.writeValue(_usageStats, '${settings.usageStats}');
  }
}
