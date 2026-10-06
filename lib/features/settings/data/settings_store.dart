import '../../../core/i18n/app_language.dart';
import '../../../data/local/app_database.dart';
import '../domain/app_settings.dart';

/// Display preferences kept in the local database (technical key/values,
/// not synchronised: a preference of this phone).
class SettingsStore {
  SettingsStore(this._db);

  final AppDatabase _db;

  static const _language = 'settings.language';
  static const _theme = 'settings.theme';
  static const _reducedMotion = 'settings.reduced_motion';

  Future<AppSettings> load() async {
    final theme = await _db.readValue(_theme);
    return AppSettings(
      language: AppLanguage.tryParse(await _db.readValue(_language)),
      theme: ThemePreference.values.firstWhere(
        (t) => t.name == theme,
        orElse: () => ThemePreference.system,
      ),
      reducedMotion: await _db.readValue(_reducedMotion) == 'true',
    );
  }

  Future<void> save(AppSettings settings) async {
    final language = settings.language;
    if (language != null) await _db.writeValue(_language, language.name);
    await _db.writeValue(_theme, settings.theme.name);
    await _db.writeValue(_reducedMotion, '${settings.reducedMotion}');
  }
}
