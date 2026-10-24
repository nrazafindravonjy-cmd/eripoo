import '../../../core/i18n/app_language.dart';

/// User display preferences (immutable value).
class AppSettings {
  const AppSettings({
    this.language,
    this.reducedMotion = false,
    this.celebrations = true,
    this.mascot = true,
    this.missionReminders = false,
    this.usageStats = false,
  });

  /// Chosen on the welcome screen (the phone's language preselected). Null until then.
  final AppLanguage? language;

  /// Eripoo-level "reduce animations", on top of the system setting.
  final bool reducedMotion;

  /// Short celebrations (a tool unlocked…); can be turned off.
  final bool celebrations;

  /// The Eripoo mascot on the welcome, step, celebration and empty screens.
  final bool mascot;

  /// Local mission reminders (CLAUDE.md §46); off until the user asks.
  final bool missionReminders;

  /// Opt-in anonymous usage statistics (decision D7); off by default.
  final bool usageStats;

  AppSettings copyWith({
    AppLanguage? Function()? language,
    bool? reducedMotion,
    bool? celebrations,
    bool? mascot,
    bool? missionReminders,
    bool? usageStats,
  }) => AppSettings(
    language: language == null ? this.language : language(),
    reducedMotion: reducedMotion ?? this.reducedMotion,
    celebrations: celebrations ?? this.celebrations,
    mascot: mascot ?? this.mascot,
    missionReminders: missionReminders ?? this.missionReminders,
    usageStats: usageStats ?? this.usageStats,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.language == language &&
      other.reducedMotion == reducedMotion &&
      other.celebrations == celebrations &&
      other.mascot == mascot &&
      other.missionReminders == missionReminders &&
      other.usageStats == usageStats;

  @override
  int get hashCode => Object.hash(
    language,
    reducedMotion,
    celebrations,
    mascot,
    missionReminders,
    usageStats,
  );
}
