/// When a local mission reminder may be shown (CLAUDE.md §46): opt-in,
/// at most one a day, in the daytime, only for a mission left waiting.
/// No streak, no guilt, no server.
abstract final class ReminderPolicy {
  /// At most one reminder per day (a little less, so a daily check at a
  /// slightly earlier hour still finds the next day's window open).
  static const minGap = Duration(hours: 20);

  /// A mission untouched for this long is worth a gentle reminder.
  static const idle = Duration(days: 2);

  /// Local hours: never in the evening or at night.
  static const firstHour = 9;
  static const endHour = 20;

  /// [lastTouched]: when each open mission (accepted or in progress) was
  /// last changed. [now] is local time.
  static bool due({
    required bool enabled,
    required Iterable<DateTime> lastTouched,
    required DateTime? lastShown,
    required DateTime now,
  }) {
    if (!enabled) return false;
    if (now.hour < firstHour || now.hour >= endHour) return false;
    if (lastShown != null && now.difference(lastShown) < minGap) return false;
    return lastTouched.any((t) => now.difference(t) >= idle);
  }
}
