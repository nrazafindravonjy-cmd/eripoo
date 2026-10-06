import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_language.dart';
import '../data/settings_store.dart';
import '../domain/app_settings.dart';

/// Settings read at start-up (overridden by bootstrap with the stored ones).
final initialSettingsProvider = Provider<AppSettings>(
  (ref) => const AppSettings(),
);

/// Where settings are saved; null keeps them in memory (widget tests).
final settingsStoreProvider = Provider<SettingsStore?>((ref) => null);

/// Holds display preferences and saves every change in the local database.
class AppSettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  void _set(AppSettings next) {
    state = next;
    final store = ref.read(settingsStoreProvider);
    if (store != null) unawaited(store.save(next));
  }

  void setTheme(ThemePreference theme) => _set(state.copyWith(theme: theme));

  void setLanguage(AppLanguage? language) =>
      _set(state.copyWith(language: () => language));

  void setReducedMotion(bool value) =>
      _set(state.copyWith(reducedMotion: value));
}

final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );
