import 'dart:convert';

import '../../../core/ids/ids.dart';
import '../../../core/time/clock.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/entity_types.dart';
import '../../../data/local/sync_tracker.dart';

enum FactSource { diagnostic, rule, user }

/// Typed facts read by content rules (`diag.idea_stage`...). Values are
/// enums, numbers or booleans — never free text, so rules never handle
/// private writing (docs/PRODUCT_ARCHITECTURE.md §2).
class FactsRepository {
  FactsRepository(this._db, {this._clock = systemClock})
    : _sync = SyncTracker(_db);

  final AppDatabase _db;
  final Clock _clock;
  final SyncTracker _sync;

  static final _keyPattern = RegExp(r'^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$');

  static void _validate(String key, Object? value) {
    if (!_keyPattern.hasMatch(key)) throw ArgumentError.value(key, 'key');
    final ok =
        value == null ||
        value is bool ||
        value is num ||
        (value is String && RegExp(r'^[a-z0-9_]{1,40}$').hasMatch(value));
    if (!ok) {
      throw ArgumentError.value(value, 'value', 'must be an enum-like token');
    }
  }

  Future<void> set(String key, Object? value, FactSource source) async {
    _validate(key, value);
    final id = Ids.forKey('fact:$key');
    final now = _clock().millisecondsSinceEpoch;
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.facts,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      await _db
          .into(_db.facts)
          .insertOnConflictUpdate(
            FactsCompanion.insert(
              id: id,
              factKey: key,
              valueJson: jsonEncode(value),
              source: source.name,
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
            ),
          );
      await _sync.markChanged(EntityTypes.fact, id);
    });
  }

  Future<Map<String, Object?>> all() async {
    final rows = await (_db.select(
      _db.facts,
    )..where((t) => t.deletedAt.isNull())).get();
    return {for (final r in rows) r.factKey: jsonDecode(r.valueJson)};
  }
}
