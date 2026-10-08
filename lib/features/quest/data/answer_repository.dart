import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/ids/ids.dart';
import '../../../core/time/clock.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/entity_types.dart';
import '../../../data/local/sync_tracker.dart';
import '../domain/answer.dart';

/// Answers to question blocks: one per block, deterministic id.
class AnswerRepository {
  AnswerRepository(this._db, {this._clock = systemClock})
    : _sync = SyncTracker(_db);

  final AppDatabase _db;
  final Clock _clock;
  final SyncTracker _sync;

  static String idOf(String stepId, String blockId) =>
      Ids.forKey('answer:$stepId/$blockId');

  static String _typeToken(AnswerType t) =>
      t == AnswerType.multiChoice ? 'multi_choice' : t.name;

  static AnswerType _typeOf(String token) => token == 'multi_choice'
      ? AnswerType.multiChoice
      : AnswerType.values.byName(token);

  Future<void> save({
    required String questId,
    required String stepId,
    required String blockId,
    required Answer answer,
  }) async {
    final id = idOf(stepId, blockId);
    final now = _clock().millisecondsSinceEpoch;
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.answers,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      await _db
          .into(_db.answers)
          .insertOnConflictUpdate(
            AnswersCompanion.insert(
              id: id,
              questId: questId,
              stepId: stepId,
              blockId: blockId,
              answerType: _typeToken(answer.type),
              valueJson: Value(
                answer.value == null ? null : jsonEncode(answer.value),
              ),
              helpUsed: Value(answer.helpUsed),
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
              deletedAt: const Value(null),
            ),
          );
      await _sync.markChanged(EntityTypes.answer, id);
    });
  }

  /// Removes an answer (a spoken answer deleted by the user): the step
  /// asks the question again.
  Future<void> delete(String stepId, String blockId) async {
    final id = idOf(stepId, blockId);
    final now = _clock().millisecondsSinceEpoch;
    await _db.transaction(() async {
      final removed =
          await (_db.update(
            _db.answers,
          )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(
            AnswersCompanion(deletedAt: Value(now), updatedAt: Value(now)),
          );
      if (removed > 0) await _sync.markChanged(EntityTypes.answer, id);
    });
  }

  Answer _toDomain(AnswerRow row) {
    final raw = row.valueJson == null ? null : jsonDecode(row.valueJson!);
    final type = _typeOf(row.answerType);
    final value = switch (type) {
      AnswerType.multiChoice => (raw! as List<Object?>).cast<String>(),
      AnswerType.money => (raw! as num).toInt(),
      _ => raw,
    };
    return Answer(type, value, helpUsed: row.helpUsed);
  }

  /// Answers of a step, by block id.
  Future<Map<String, Answer>> forStep(String stepId) async {
    final rows = await (_db.select(
      _db.answers,
    )..where((t) => t.stepId.equals(stepId) & t.deletedAt.isNull())).get();
    return {for (final r in rows) r.blockId: _toDomain(r)};
  }

  /// "I don't know" answers per quest (read by rules: counts only).
  Future<Map<String, int>> unknownCountByQuest() async {
    final rows =
        await (_db.select(_db.answers)..where(
              (t) => t.answerType.equals('unknown') & t.deletedAt.isNull(),
            ))
            .get();
    final counts = <String, int>{};
    for (final r in rows) {
      counts[r.questId] = (counts[r.questId] ?? 0) + 1;
    }
    return counts;
  }

  Stream<void> watchChanges() => _db.select(_db.answers).watch().map((_) {});
}
