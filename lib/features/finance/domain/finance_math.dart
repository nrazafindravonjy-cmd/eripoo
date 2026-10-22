/// The finance calculators (CLAUDE.md §17), pure and exact.
///
/// Amounts are whole ariary (`int`), rates are basis points (1 % = 100):
/// no floating point anywhere, so a result never depends on rounding
/// noise. Every input is bounded so that no product or 12-month sum can
/// overflow a 64-bit integer: 10^11 Ar × 10^6 units × 12 months < 2^63.
library;

/// The inputs of the calculators.
enum FinanceField {
  amount,
  firstVolume,
  fixedMonthly,
  investment,
  lastVolume,
  marginBp,
  months,
  need,
  price,
  sources,
  startingCash,
  unitCost,
  volumes,
}

/// A value outside what the calculators accept.
class InvalidFinanceInput implements Exception {
  const InvalidFinanceInput(this.field);

  /// Which input is wrong (for the form to point at it).
  final FinanceField field;

  @override
  String toString() => 'InvalidFinanceInput(${field.name})';
}

abstract final class FinanceLimits {
  /// One amount: 100 billion ariary, far above a small business.
  static const maxAmount = 100000000000;

  /// Units sold in one month.
  static const maxMonthlyVolume = 1000000;

  /// A margin on the selling price is always below 100 %.
  static const maxMarginBp = 9900;

  /// Markup on the cost: up to +1 000 %.
  static const maxMarkupBp = 100000;

  /// Items of one kind summed together (costs, sources of money).
  static const maxItems = 200;

  /// Length of the cash plan.
  static const planMonths = 12;
}

int _amount(int value, FinanceField field) {
  if (value < 0 || value > FinanceLimits.maxAmount) {
    throw InvalidFinanceInput(field);
  }
  return value;
}

int _volume(int value, FinanceField field) {
  if (value < 0 || value > FinanceLimits.maxMonthlyVolume) {
    throw InvalidFinanceInput(field);
  }
  return value;
}

/// Ceiling of a / b for a ≥ 0, b > 0.
int _ceilDiv(int a, int b) => (a + b - 1) ~/ b;

/// a / b rounded to the nearest, halves away from zero (b > 0).
int _roundDiv(int a, int b) {
  final q = a.abs() * 2 + b;
  final r = q ~/ (2 * b);
  return a < 0 ? -r : r;
}

/// Sum of amounts, each checked; at most [FinanceLimits.maxItems].
int sumAmounts(
  Iterable<int> amounts, {
  FinanceField field = FinanceField.amount,
}) {
  var total = 0;
  var count = 0;
  for (final a in amounts) {
    if (++count > FinanceLimits.maxItems) throw InvalidFinanceInput(field);
    total += _amount(a, field);
  }
  return total;
}

// ---------------------------------------------------------------- price

/// The selling price that leaves [marginBp] of it once the unit cost is
/// paid: price = cost / (1 − margin), rounded up to the next ariary so the
/// margin is never below what was asked.
class PriceSuggestion {
  const PriceSuggestion({
    required this.unitCost,
    required this.marginBp,
    required this.price,
    required this.markupBp,
  });

  final int unitCost;
  final int marginBp;
  final int price;

  /// The same price seen from the cost: (price − cost) / cost. Null when
  /// the cost is zero.
  final int? markupBp;

  int get unitMargin => price - unitCost;
}

PriceSuggestion suggestPrice({required int unitCost, required int marginBp}) {
  _amount(unitCost, FinanceField.unitCost);
  if (marginBp < 0 || marginBp > FinanceLimits.maxMarginBp) {
    throw const InvalidFinanceInput(FinanceField.marginBp);
  }
  final price = _ceilDiv(unitCost * 10000, 10000 - marginBp);
  if (price > FinanceLimits.maxAmount) {
    throw const InvalidFinanceInput(FinanceField.unitCost);
  }
  return PriceSuggestion(
    unitCost: unitCost,
    marginBp: marginBp,
    price: price,
    markupBp: unitCost == 0
        ? null
        : _roundDiv((price - unitCost) * 10000, unitCost),
  );
}

/// Prices seen elsewhere (competitors): lowest, middle, highest.
class PriceRange {
  const PriceRange({
    required this.low,
    required this.median,
    required this.high,
  });

  final int low;

  /// Middle value; the rounded mean of the two middle ones for an even
  /// count.
  final int median;
  final int high;

  /// Null when there is no price.
  static PriceRange? of(Iterable<int> prices) {
    final sorted = [for (final p in prices) _amount(p, FinanceField.price)]
      ..sort();
    if (sorted.isEmpty) return null;
    final mid = sorted.length ~/ 2;
    final median = sorted.length.isOdd
        ? sorted[mid]
        : _roundDiv(sorted[mid - 1] + sorted[mid], 2);
    return PriceRange(low: sorted.first, median: median, high: sorted.last);
  }

  /// Where [price] stands: -1 below the lowest, 1 above the highest, 0
  /// inside.
  int position(int price) => price < low ? -1 : (price > high ? 1 : 0);
}

// ---------------------------------------------------------------- margin

/// What is left on one unit sold.
class Margin {
  const Margin({
    required this.price,
    required this.unitCost,
    required this.marginBp,
    required this.markupBp,
  });

  final int price;
  final int unitCost;

  /// Share of the price that is left (can be negative). Null if the price
  /// is zero.
  final int? marginBp;

  /// Increase over the cost (can be negative). Null if the cost is zero.
  final int? markupBp;

  int get unitMargin => price - unitCost;
  bool get isLoss => unitMargin < 0;
}

Margin margin({required int price, required int unitCost}) {
  _amount(price, FinanceField.price);
  _amount(unitCost, FinanceField.unitCost);
  final unitMargin = price - unitCost;
  return Margin(
    price: price,
    unitCost: unitCost,
    marginBp: price == 0 ? null : _roundDiv(unitMargin * 10000, price),
    markupBp: unitCost == 0 ? null : _roundDiv(unitMargin * 10000, unitCost),
  );
}

// ---------------------------------------------------------------- break-even

/// How many units must be sold each month to pay the monthly fixed costs.
class BreakEven {
  const BreakEven._({
    required this.fixedMonthly,
    required this.unitMargin,
    this.units,
    this.revenue,
  });

  final int fixedMonthly;
  final int unitMargin;

  /// Units per month, rounded up. Null when no volume can reach it (each
  /// unit loses money or earns nothing while there are fixed costs).
  final int? units;

  /// Monthly sales at the break-even point. Null when [units] is null or
  /// beyond [FinanceLimits.maxMonthlyVolume].
  final int? revenue;

  bool get reachable => units != null;

  /// More than [FinanceLimits.maxMonthlyVolume] a month: not realistic.
  bool get beyondLimits => units != null && revenue == null;
}

BreakEven breakEven({
  required int fixedMonthly,
  required int price,
  required int unitCost,
}) {
  _amount(fixedMonthly, FinanceField.fixedMonthly);
  _amount(price, FinanceField.price);
  _amount(unitCost, FinanceField.unitCost);
  final unitMargin = price - unitCost;
  if (fixedMonthly == 0) {
    return BreakEven._(
      fixedMonthly: 0,
      unitMargin: unitMargin,
      units: unitMargin >= 0 ? 0 : null,
      revenue: unitMargin >= 0 ? 0 : null,
    );
  }
  if (unitMargin <= 0) {
    return BreakEven._(fixedMonthly: fixedMonthly, unitMargin: unitMargin);
  }
  final units = _ceilDiv(fixedMonthly, unitMargin);
  return BreakEven._(
    fixedMonthly: fixedMonthly,
    unitMargin: unitMargin,
    units: units,
    revenue: units > FinanceLimits.maxMonthlyVolume ? null : units * price,
  );
}

// ---------------------------------------------------------------- cash plan

/// Monthly volumes going in a straight line from [first] to [last] over
/// [months] months, rounded to whole units.
List<int> rampVolumes({
  required int first,
  required int last,
  int months = FinanceLimits.planMonths,
}) {
  _volume(first, FinanceField.firstVolume);
  _volume(last, FinanceField.lastVolume);
  if (months < 1) throw const InvalidFinanceInput(FinanceField.months);
  if (months == 1) return [first];
  return [
    for (var m = 0; m < months; m++)
      first + _roundDiv((last - first) * m, months - 1),
  ];
}

class CashMonth {
  const CashMonth({
    required this.month,
    required this.volume,
    required this.revenue,
    required this.costs,
    required this.closing,
  });

  /// 1 to 12.
  final int month;
  final int volume;
  final int revenue;

  /// Fixed costs plus the cost of the units sold.
  final int costs;

  /// Money available at the end of the month (negative = missing).
  final int closing;

  int get net => revenue - costs;
}

/// Money month by month: what comes in at the start, minus the
/// investment, then each month's sales minus its costs.
class CashPlan {
  const CashPlan({
    required this.startingCash,
    required this.investment,
    required this.months,
  });

  final int startingCash;
  final int investment;
  final List<CashMonth> months;

  /// Lowest balance, the start (after the investment) included.
  int get lowest => months.fold(
    startingCash - investment,
    (low, m) => m.closing < low ? m.closing : low,
  );

  /// First month that ends with missing money; 0 if the investment alone
  /// already exceeds the starting money; null if never.
  int? get firstShortMonth {
    if (startingCash - investment < 0) return 0;
    for (final m in months) {
      if (m.closing < 0) return m.month;
    }
    return null;
  }

  /// Money needed from outside so the balance never goes below zero.
  int get need => lowest < 0 ? -lowest : 0;

  /// First month whose own sales cover its costs; null if none.
  int? get firstProfitableMonth {
    for (final m in months) {
      if (m.net > 0) return m.month;
    }
    return null;
  }
}

CashPlan cashPlan({
  required int startingCash,
  required int investment,
  required List<int> volumes,
  required int price,
  required int unitCost,
  required int fixedMonthly,
}) {
  _amount(startingCash, FinanceField.startingCash);
  _amount(investment, FinanceField.investment);
  _amount(price, FinanceField.price);
  _amount(unitCost, FinanceField.unitCost);
  _amount(fixedMonthly, FinanceField.fixedMonthly);
  if (volumes.isEmpty || volumes.length > FinanceLimits.planMonths) {
    throw const InvalidFinanceInput(FinanceField.volumes);
  }
  var balance = startingCash - investment;
  final months = <CashMonth>[];
  for (var i = 0; i < volumes.length; i++) {
    final volume = _volume(volumes[i], FinanceField.volumes);
    final revenue = volume * price;
    final costs = fixedMonthly + volume * unitCost;
    balance += revenue - costs;
    months.add(
      CashMonth(
        month: i + 1,
        volume: volume,
        revenue: revenue,
        costs: costs,
        closing: balance,
      ),
    );
  }
  return CashPlan(
    startingCash: startingCash,
    investment: investment,
    months: months,
  );
}

// ---------------------------------------------------------------- financing

/// What the project needs against the money already found.
class FundingGap {
  const FundingGap({required this.need, required this.found});

  final int need;
  final int found;

  /// Still missing (0 when covered).
  int get missing => need > found ? need - found : 0;

  /// More than needed.
  int get surplus => found > need ? found - need : 0;

  bool get covered => found >= need;
}

/// [need] is usually [CashPlan.need] of a plan started with no money.
FundingGap fundingGap({required int need, required Iterable<int> sources}) {
  if (need < 0) throw const InvalidFinanceInput(FinanceField.need);
  return FundingGap(
    need: need,
    found: sumAmounts(sources, field: FinanceField.sources),
  );
}

/// Months of profit needed to get back [investment]; null when the
/// monthly profit is zero or negative.
int? monthsToRecover({required int investment, required int monthlyProfit}) {
  _amount(investment, FinanceField.investment);
  if (monthlyProfit <= 0) return null;
  if (investment == 0) return 0;
  return _ceilDiv(investment, monthlyProfit);
}

/// A percentage typed by the user (`30`, `12,5`, `12.5`) as basis
/// points; at most two decimals. Null when it is not a number.
int? parsePercentBp(String text) {
  final t = text.trim().replaceAll(' ', '').replaceAll('%', '');
  final match = RegExp(r'^(\d{1,4})(?:[.,](\d{1,2}))?$').firstMatch(t);
  if (match == null) return null;
  final whole = int.parse(match.group(1)!);
  final decimals = (match.group(2) ?? '').padRight(2, '0');
  return whole * 100 + int.parse(decimals);
}

/// An ariary amount typed by the user, spaces and dots between thousands
/// allowed (`15 000`, `15.000`). Null when it is not a whole number.
int? parseAmount(String text) {
  final t = text.trim().replaceAll(RegExp(r'[\s.]'), '');
  if (!RegExp(r'^\d{1,12}$').hasMatch(t)) return null;
  return int.parse(t);
}
