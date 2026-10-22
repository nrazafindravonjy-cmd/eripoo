import 'dart:convert';

import '../../../data/local/app_database.dart';
import '../domain/usage_event.dart';

/// Sends a batch of totals (`{"event": count}`) for this app version.
typedef UsageSink = Future<void> Function(Map<String, int> totals);

/// Opt-in usage statistics (decision D7, CLAUDE.md §45): counts kept on
/// the phone, then sent as anonymous totals. Off until the user agrees;
/// turning it off drops what was not sent.
class UsageCounter {
  UsageCounter(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// The setting (shared with SettingsStore).
  static const enabledKey = 'settings.usage_stats';
  static const _pendingKey = 'usage.pending';
  static const _openedKey = 'usage.opened_day';

  /// The server accepts at most this much per event and batch.
  static const maxPerEvent = 100;

  Future<bool> get enabled async => await _db.readValue(enabledKey) == 'true';

  Future<Map<String, int>> _pending() async {
    final raw = await _db.readValue(_pendingKey);
    if (raw == null) return {};
    return (jsonDecode(raw) as Map<String, Object?>).map(
      (k, v) => MapEntry(k, v! as int),
    );
  }

  /// Counts [event] if the user agreed. "App opened" counts once a day.
  Future<void> record(UsageEvent event) async {
    if (!await enabled) return;
    if (event == UsageEvent.appOpened) {
      final now = _clock();
      final day = '${now.year}-${now.month}-${now.day}';
      if (await _db.readValue(_openedKey) == day) return;
      await _db.writeValue(_openedKey, day);
    }
    final pending = await _pending();
    final count = (pending[event.token] ?? 0) + 1;
    pending[event.token] = count > maxPerEvent ? maxPerEvent : count;
    await _db.writeValue(_pendingKey, jsonEncode(pending));
  }

  /// Sends what is pending; kept for later if sending fails.
  Future<void> flush(UsageSink send) async {
    if (!await enabled) return;
    final pending = await _pending();
    if (pending.isEmpty) return;
    await send(pending);
    await _db.deleteValue(_pendingKey);
  }

  /// Turning the statistics off forgets what was not sent.
  Future<void> forgetPending() => _db.deleteValue(_pendingKey);
}
