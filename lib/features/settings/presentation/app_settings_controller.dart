import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_language.dart';
import '../domain/app_settings.dart';

/// Holds display preferences.
///
/// ⚠️ In memory only: settings reset when the app restarts. Persistence in
/// the local database comes with Drift in Phase 2 (docs/DEVELOPMENT_PLAN.md).
class AppSettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => const AppSettings();

  void setTheme(ThemePreference theme) => state = state.copyWith(theme: theme);

  void setLanguage(AppLanguage? language) =>
      state = state.copyWith(language: () => language);

  void setReducedMotion(bool value) =>
      state = state.copyWith(reducedMotion: value);
}

final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );
