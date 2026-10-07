import 'package:drift/drift.dart';

import '../../../core/ids/ids.dart';
import '../../../core/time/clock.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/entity_types.dart';
import '../../../data/local/sync_tracker.dart';
import '../domain/finance_math.dart';

/// What an amount of the project is.
enum FinanceKind {
  /// What one unit sold costs (materials, packaging).
  variableCost('variable_cost'),

  /// What each month costs whatever is sold (rent, phone credit, salary).
  fixedCost('fixed_cost'),

  /// Bought once before starting (equipment, first stock).
  investment('investment'),

  /// Money found to start.
  funding('funding');

  const FinanceKind(this.stored);
  final String stored;

  static FinanceKind fromStored(String value) =>
      values.firstWhere((k) => k.stored == value);
}

/// Where money found comes from (CLAUDE.md §49). The kinds only: no
/// institution is named (nothing about them is verified yet).
enum FundingSource { own, family, microfinance, bank, investor, grant, other }

class FinanceItem {
  const FinanceItem({
    required this.id,
    required this.kind,
    required this.label,
    required this.amountMga,
    this.source,
  });

  final String id;
  final FinanceKind kind;
  final String label;
  final int amountMga;
  final FundingSource? source;
}

/// The price chosen and the sales expected.
class FinancePlan {
  const FinancePlan({this.priceMga, this.volumeFirst, this.volumeLast});

  final int? priceMga;
  final int? volumeFirst;
  final int? volumeLast;

  static const empty = FinancePlan();
}

/// The input is refused (empty or too long label, amount out of range,
/// too many items, source on a cost).
class InvalidFinanceItem implements Exception {
  const InvalidFinanceItem();
}

abstract final class FinanceItemRules {
  static const maxLabelLength = 80;
}

/// Everything the calculators need for one project, with the results
/// already computed (or null when an input is still missing).
class FinanceSnapshot {
  FinanceSnapshot({required this.items, required this.plan});

  final List<FinanceItem> items;
  final FinancePlan plan;

  List<FinanceItem> ofKind(FinanceKind kind) => [
    for (final i in items)
      if (i.kind == kind) i,
  ];

  int _sum(FinanceKind kind) =>
      sumAmounts(ofKind(kind).map((i) => i.amountMga));

  /// Sum of what one unit costs.
  late final int unitCost = _sum(FinanceKind.variableCost);
  late final int fixedMonthly = _sum(FinanceKind.fixedCost);
  late final int investment = _sum(FinanceKind.investment);
  late final int funding = _sum(FinanceKind.funding);

  bool get hasUnitCost => ofKind(FinanceKind.variableCost).isNotEmpty;
  bool get hasVolumes => plan.volumeFirst != null && plan.volumeLast != null;

  /// Null until a price is chosen.
  late final Margin? unitMargin = plan.priceMga == null
      ? null
      : margin(price: plan.priceMga!, unitCost: unitCost);

  late final BreakEven? breakEvenPoint = plan.priceMga == null
      ? null
      : breakEven(
          fixedMonthly: fixedMonthly,
          price: plan.priceMga!,
          unitCost: unitCost,
        );

  List<int>? get _volumes => hasVolumes
      ? rampVolumes(first: plan.volumeFirst!, last: plan.volumeLast!)
      : null;

  CashPlan? _plan(int startingCash) => plan.priceMga == null || !hasVolumes
      ? null
      : cashPlan(
          startingCash: startingCash,
          investment: investment,
          volumes: _volumes!,
          price: plan.priceMga!,
          unitCost: unitCost,
          fixedMonthly: fixedMonthly,
        );

  /// Month by month with the money found. Null until price and volumes
  /// are set.
  late final CashPlan? cash = _plan(funding);

  /// What the project needs from outside, and what is still missing.
  late final FundingGap? gap = switch (_plan(0)) {
    null => null,
    final p => fundingGap(
      need: p.need,
      sources: ofKind(FinanceKind.funding).map((i) => i.amountMga),
    ),
  };
}

/// The money of a project, kept by the user and synchronised encrypted;
/// amounts are deleted through the trash.
class FinanceService {
  FinanceService(this._db, {this._clock = systemClock})
    : _sync = SyncTracker(_db);

  final AppDatabase _db;
  final Clock _clock;
  final SyncTracker _sync;

  int _now() => _clock().millisecondsSinceEpoch;

  static String planIdOf(String projectId) =>
      Ids.forKey('finance_plan:$projectId');

  static FinanceItem _toDomain(FinanceItemRow r) => FinanceItem(
    id: r.id,
    kind: FinanceKind.fromStored(r.kind),
    label: r.label,
    amountMga: r.amountMga,
    source: r.source == null ? null : FundingSource.values.byName(r.source!),
  );

  static String _label(String value) {
    final t = value.trim();
    if (t.isEmpty || t.length > FinanceItemRules.maxLabelLength) {
      throw const InvalidFinanceItem();
    }
    return t;
  }

  static int _amountMga(int value) {
    if (value < 0 || value > FinanceLimits.maxAmount) {
      throw const InvalidFinanceItem();
    }
    return value;
  }

  static String? _source(FinanceKind kind, FundingSource? source) {
    if ((kind == FinanceKind.funding) != (source != null)) {
      throw const InvalidFinanceItem();
    }
    return source?.name;
  }

  Future<List<FinanceItem>> itemsOf(String projectId) async => [
    for (final r
        in await (_db.select(_db.financeItems)
              ..where(
                (t) => t.projectId.equals(projectId) & t.deletedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get())
      _toDomain(r),
  ];

  Future<FinancePlan> planOf(String projectId) async {
    final row = await (_db.select(
      _db.financePlans,
    )..where((t) => t.id.equals(planIdOf(projectId)))).getSingleOrNull();
    if (row == null || row.deletedAt != null) return FinancePlan.empty;
    return FinancePlan(
      priceMga: row.priceMga,
      volumeFirst: row.volumeFirst,
      volumeLast: row.volumeLast,
    );
  }

  Future<FinanceSnapshot> snapshot(String projectId) async => FinanceSnapshot(
    items: await itemsOf(projectId),
    plan: await planOf(projectId),
  );

  Future<FinanceItem> add({
    required String projectId,
    required FinanceKind kind,
    required String label,
    required int amountMga,
    FundingSource? source,
  }) => _db.transaction(() async {
    final count =
        await (_db.selectOnly(_db.financeItems)
              ..addColumns([_db.financeItems.id.count()])
              ..where(
                _db.financeItems.projectId.equals(projectId) &
                    _db.financeItems.kind.equals(kind.stored) &
                    _db.financeItems.deletedAt.isNull(),
              ))
            .map((r) => r.read(_db.financeItems.id.count())!)
            .getSingle();
    if (count >= FinanceLimits.maxItems) throw const InvalidFinanceItem();
    final id = Ids.newId();
    final now = _now();
    await _db
        .into(_db.financeItems)
        .insert(
          FinanceItemsCompanion.insert(
            id: id,
            projectId: projectId,
            kind: kind.stored,
            source: Value(_source(kind, source)),
            label: _label(label),
            amountMga: _amountMga(amountMga),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _sync.markChanged(EntityTypes.financeItem, id);
    return (await _get(id))!;
  });

  Future<FinanceItem> update(
    String id, {
    required String label,
    required int amountMga,
    FundingSource? source,
  }) => _db.transaction(() async {
    final current = await _get(id);
    if (current == null) throw StateError('Unknown finance item');
    final count =
        await (_db.update(
          _db.financeItems,
        )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(
          FinanceItemsCompanion(
            label: Value(_label(label)),
            amountMga: Value(_amountMga(amountMga)),
            source: Value(_source(current.kind, source)),
            updatedAt: Value(_now()),
          ),
        );
    if (count == 0) throw StateError('Unknown finance item');
    await _sync.markChanged(EntityTypes.financeItem, id);
    return (await _get(id))!;
  });

  /// Saves the price and the sales expected; null clears a value.
  Future<void> savePlan(
    String projectId, {
    required int? priceMga,
    required int? volumeFirst,
    required int? volumeLast,
  }) => _db.transaction(() async {
    if (priceMga != null) _amountMga(priceMga);
    for (final v in [volumeFirst, volumeLast]) {
      if (v != null && (v < 0 || v > FinanceLimits.maxMonthlyVolume)) {
        throw const InvalidFinanceItem();
      }
    }
    final id = planIdOf(projectId);
    final now = _now();
    final existing = await (_db.select(
      _db.financePlans,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    await _db
        .into(_db.financePlans)
        .insertOnConflictUpdate(
          FinancePlansCompanion.insert(
            id: id,
            projectId: projectId,
            priceMga: Value(priceMga),
            volumeFirst: Value(volumeFirst),
            volumeLast: Value(volumeLast),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
    await _sync.markChanged(EntityTypes.financePlan, id);
  });

  Future<FinanceItem?> _get(String id) async {
    final row = await (_db.select(
      _db.financeItems,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null || row.deletedAt != null ? null : _toDomain(row);
  }

  Stream<void> watchChanges() => _db.tableUpdates(
    TableUpdateQuery.onAllTables([_db.financeItems, _db.financePlans]),
  );
}
