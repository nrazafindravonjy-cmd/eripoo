import '../../../core/i18n/app_language.dart';

enum ThemePreference { system, light, dark }

/// User display preferences (immutable value).
class AppSettings {
  const AppSettings({
    this.theme = ThemePreference.system,
    this.language,
    this.reducedMotion = false,
  });

  final ThemePreference theme;

  /// Chosen on the welcome screen (Malagasy preselected). Null until then.
  final AppLanguage? language;

  /// Eripoo-level "reduce animations", on top of the system setting.
  final bool reducedMotion;

  AppSettings copyWith({
    ThemePreference? theme,
    AppLanguage? Function()? language,
    bool? reducedMotion,
  }) => AppSettings(
    theme: theme ?? this.theme,
    language: language == null ? this.language : language(),
    reducedMotion: reducedMotion ?? this.reducedMotion,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.theme == theme &&
      other.language == language &&
      other.reducedMotion == reducedMotion;

  @override
  int get hashCode => Object.hash(theme, language, reducedMotion);
}
