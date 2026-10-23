import '../../../core/i18n/app_language.dart';

enum ThemePreference { system, light, dark }

/// User display preferences (immutable value).
class AppSettings {
  const AppSettings({
    this.theme = ThemePreference.system,
    this.language,
    this.reducedMotion = false,
    this.celebrations = true,
    this.missionReminders = false,
    this.usageStats = false,
  });

  final ThemePreference theme;

  /// Chosen on the welcome screen (the phone's language preselected). Null until then.
  final AppLanguage? language;

  /// Eripoo-level "reduce animations", on top of the system setting.
  final bool reducedMotion;

  /// Short celebrations (a tool unlocked…); can be turned off.
  final bool celebrations;

  /// Local mission reminders (CLAUDE.md §46); off until the user asks.
  final bool missionReminders;

  /// Opt-in anonymous usage statistics (decision D7); off by default.
  final bool usageStats;

  AppSettings copyWith({
    ThemePreference? theme,
    AppLanguage? Function()? language,
    bool? reducedMotion,
    bool? celebrations,
    bool? missionReminders,
    bool? usageStats,
  }) => AppSettings(
    theme: theme ?? this.theme,
    language: language == null ? this.language : language(),
    reducedMotion: reducedMotion ?? this.reducedMotion,
    celebrations: celebrations ?? this.celebrations,
    missionReminders: missionReminders ?? this.missionReminders,
    usageStats: usageStats ?? this.usageStats,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.theme == theme &&
      other.language == language &&
      other.reducedMotion == reducedMotion &&
      other.celebrations == celebrations &&
      other.missionReminders == missionReminders &&
      other.usageStats == usageStats;

  @override
  int get hashCode => Object.hash(
    theme,
    language,
    reducedMotion,
    celebrations,
    missionReminders,
    usageStats,
  );
}
