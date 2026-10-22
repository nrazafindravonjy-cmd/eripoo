import 'package:drift/drift.dart';

import '../../../core/ids/ids.dart';
import '../../../core/time/clock.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/entity_types.dart';
import '../../../data/local/sync_tracker.dart';

/// What people use instead of the project.
enum CompetitorKind {
  /// Offers the same thing.
  direct,

  /// Answers the same need differently.
  indirect,

  /// What people do without buying: themselves, a neighbour, nothing.
  alternative,
}

class Competitor {
  const Competitor({
    required this.id,
    required this.name,
    required this.kind,
    this.offer,
    this.priceMga,
    this.strengths,
    this.weaknesses,
  });

  final String id;
  final String name;
  final CompetitorKind kind;
  final String? offer;
  final int? priceMga;
  final String? strengths;
  final String? weaknesses;
}

/// The input is refused (empty name, text too long, negative price).
class InvalidCompetitor implements Exception {
  const InvalidCompetitor();
}

abstract final class CompetitorRules {
  static const maxNameLength = 80;
  static const maxTextLength = 500;

  /// 100 million ariary: beyond, surely a typing mistake.
  static const maxPriceMga = 100000000;
}

/// The competitor analysis (CLAUDE.md §20): written by the user from what
/// they saw or heard; synchronised encrypted like every project record,
/// deleted through the trash.
class CompetitorService {
  CompetitorService(this._db, {this._clock = systemClock})
    : _sync = SyncTracker(_db);

  final AppDatabase _db;
  final Clock _clock;
  final SyncTracker _sync;

  int _now() => _clock().millisecondsSinceEpoch;

  static Competitor _toDomain(CompetitorRow r) => Competitor(
    id: r.id,
    name: r.name,
    kind: CompetitorKind.values.byName(r.kind),
    offer: r.offer,
    priceMga: r.priceMga,
    strengths: r.strengths,
    weaknesses: r.weaknesses,
  );

  static String? _text(String? value) {
    final t = value?.trim();
    if (t == null || t.isEmpty) return null;
    if (t.length > CompetitorRules.maxTextLength) {
      throw const InvalidCompetitor();
    }
    return t;
  }

  static String _name(String value) {
    final t = value.trim();
    if (t.isEmpty || t.length > CompetitorRules.maxNameLength) {
      throw const InvalidCompetitor();
    }
    return t;
  }

  static int? _price(int? value) {
    if (value == null) return null;
    if (value < 0 || value > CompetitorRules.maxPriceMga) {
      throw const InvalidCompetitor();
    }
    return value;
  }

  Future<List<Competitor>> competitorsOf(String projectId) async => [
    for (final r
        in await (_db.select(_db.competitors)
              ..where(
                (t) => t.projectId.equals(projectId) & t.deletedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get())
      _toDomain(r),
  ];

  Future<Competitor> add({
    required String projectId,
    required String name,
    required CompetitorKind kind,
    String? offer,
    int? priceMga,
    String? strengths,
    String? weaknesses,
  }) => _db.transaction(() async {
    final id = Ids.newId();
    final now = _now();
    await _db
        .into(_db.competitors)
        .insert(
          CompetitorsCompanion.insert(
            id: id,
            projectId: projectId,
            name: _name(name),
            kind: kind.name,
            offer: Value(_text(offer)),
            priceMga: Value(_price(priceMga)),
            strengths: Value(_text(strengths)),
            weaknesses: Value(_text(weaknesses)),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _sync.markChanged(EntityTypes.competitor, id);
    return (await _get(id))!;
  });

  Future<Competitor> update(
    String id, {
    required String name,
    required CompetitorKind kind,
    String? offer,
    int? priceMga,
    String? strengths,
    String? weaknesses,
  }) => _db.transaction(() async {
    final count =
        await (_db.update(
          _db.competitors,
        )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(
          CompetitorsCompanion(
            name: Value(_name(name)),
            kind: Value(kind.name),
            offer: Value(_text(offer)),
            priceMga: Value(_price(priceMga)),
            strengths: Value(_text(strengths)),
            weaknesses: Value(_text(weaknesses)),
            updatedAt: Value(_now()),
          ),
        );
    if (count == 0) throw StateError('Unknown competitor');
    await _sync.markChanged(EntityTypes.competitor, id);
    return (await _get(id))!;
  });

  Future<Competitor?> _get(String id) async {
    final row = await (_db.select(
      _db.competitors,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  Stream<void> watchChanges() =>
      _db.tableUpdates(TableUpdateQuery.onAllTables([_db.competitors]));
}
