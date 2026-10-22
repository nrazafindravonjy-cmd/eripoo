// The finance calculators at their limits (Phase 7 exit criterion):
// zero, maximum, rounding, impossible cases, refused inputs, no overflow.
import 'package:eripoo/features/finance/domain/finance_math.dart';
import 'package:flutter_test/flutter_test.dart';

const max = FinanceLimits.maxAmount;
const maxVolume = FinanceLimits.maxMonthlyVolume;

Matcher refused(FinanceField field) =>
    throwsA(isA<InvalidFinanceInput>().having((e) => e.field, 'field', field));

void main() {
  group('price', () {
    test('a soap costing 600 Ar with a 40 % margin sells 1 000 Ar', () {
      final s = suggestPrice(unitCost: 600, marginBp: 4000);
      expect(s.price, 1000);
      expect(s.unitMargin, 400);
      expect(s.markupBp, 6667, reason: '+66,67 % on the cost');
    });

    test('rounded up: the margin is never below what was asked', () {
      final s = suggestPrice(unitCost: 1000, marginBp: 3000);
      expect(s.price, 1429, reason: '1 428,57… → 1 429');
      expect(margin(price: s.price, unitCost: 1000).marginBp, 3002);
      for (var cost = 1; cost < 3000; cost += 7) {
        for (final bp in [1, 999, 3333, 5000, 9900]) {
          final p = suggestPrice(unitCost: cost, marginBp: bp).price;
          expect((p - cost) * 10000 >= bp * p, isTrue, reason: '$cost $bp');
          expect((p - 1 - cost) * 10000 < bp * (p - 1), isTrue);
        }
      }
    });

    test('limits: zero cost, zero margin, 99 %, maximum', () {
      expect(suggestPrice(unitCost: 0, marginBp: 5000).price, 0);
      expect(suggestPrice(unitCost: 0, marginBp: 5000).markupBp, isNull);
      expect(suggestPrice(unitCost: 750, marginBp: 0).price, 750);
      expect(suggestPrice(unitCost: 1, marginBp: 9900).price, 100);
      expect(suggestPrice(unitCost: max, marginBp: 0).price, max);
      expect(
        () => suggestPrice(unitCost: max, marginBp: 1),
        refused(FinanceField.unitCost),
        reason: 'the price would pass the maximum amount',
      );
      expect(
        () => suggestPrice(unitCost: 10, marginBp: 10000),
        refused(FinanceField.marginBp),
      );
      expect(
        () => suggestPrice(unitCost: 10, marginBp: -1),
        refused(FinanceField.marginBp),
      );
      expect(
        () => suggestPrice(unitCost: -1, marginBp: 0),
        refused(FinanceField.unitCost),
      );
    });

    test('competitor prices: lowest, middle, highest', () {
      expect(PriceRange.of([]), isNull);
      final one = PriceRange.of([1500])!;
      expect([one.low, one.median, one.high], [1500, 1500, 1500]);
      final odd = PriceRange.of([2000, 800, 1500])!;
      expect([odd.low, odd.median, odd.high], [800, 1500, 2000]);
      final even = PriceRange.of([1000, 1001, 400, 3000])!;
      expect(even.median, 1001, reason: '1 000,5 rounded half up');
      expect(even.position(399), -1);
      expect(even.position(400), 0);
      expect(even.position(3000), 0);
      expect(even.position(3001), 1);
      expect(() => PriceRange.of([-5]), refused(FinanceField.price));
    });
  });

  group('margin', () {
    test('margin on the price and markup on the cost differ', () {
      final m = margin(price: 1000, unitCost: 750);
      expect(m.unitMargin, 250);
      expect(m.marginBp, 2500);
      expect(m.markupBp, 3333);
      expect(m.isLoss, isFalse);
    });

    test('a loss is shown, not hidden', () {
      final m = margin(price: 500, unitCost: 600);
      expect(m.unitMargin, -100);
      expect(m.marginBp, -2000);
      expect(m.markupBp, -1667);
      expect(m.isLoss, isTrue);
    });

    test('limits: zero price, zero cost, maximum', () {
      expect(margin(price: 0, unitCost: 100).marginBp, isNull);
      expect(margin(price: 100, unitCost: 0).markupBp, isNull);
      expect(margin(price: 100, unitCost: 0).marginBp, 10000);
      expect(margin(price: 0, unitCost: 0).unitMargin, 0);
      expect(margin(price: max, unitCost: 1).marginBp, 10000);
      expect(margin(price: 1, unitCost: max).marginBp, -max * 10000 + 10000);
      expect(
        () => margin(price: max + 1, unitCost: 0),
        refused(FinanceField.price),
      );
    });
  });

  group('break-even', () {
    test('fixed costs / margin per unit, rounded up', () {
      final b = breakEven(fixedMonthly: 120000, price: 1000, unitCost: 600);
      expect(b.unitMargin, 400);
      expect(b.units, 300);
      expect(b.revenue, 300000);
      final odd = breakEven(fixedMonthly: 100001, price: 1000, unitCost: 600);
      expect(odd.units, 251, reason: '250,0025 → 251');
      expect(odd.units! * odd.unitMargin >= 100001, isTrue);
    });

    test('impossible when each unit earns nothing or loses money', () {
      for (final price in [600, 500]) {
        final b = breakEven(fixedMonthly: 50000, price: price, unitCost: 600);
        expect(b.reachable, isFalse);
        expect(b.units, isNull);
        expect(b.revenue, isNull);
      }
    });

    test('no fixed costs: reached at once, unless each unit loses money', () {
      expect(breakEven(fixedMonthly: 0, price: 600, unitCost: 600).units, 0);
      expect(
        breakEven(fixedMonthly: 0, price: 500, unitCost: 600).reachable,
        isFalse,
      );
    });

    test('beyond what a month can sell: units given, no revenue', () {
      final b = breakEven(fixedMonthly: max, price: 2, unitCost: 1);
      expect(b.units, max);
      expect(b.beyondLimits, isTrue);
      expect(b.revenue, isNull);
      final edge = breakEven(
        fixedMonthly: maxVolume,
        price: max,
        unitCost: max - 1,
      );
      expect(edge.units, maxVolume);
      expect(edge.revenue, maxVolume * max, reason: 'no overflow at the edge');
    });
  });

  group('cash plan', () {
    test('ramp from first to last month, exact ends, never going back', () {
      final v = rampVolumes(first: 100, last: 400);
      expect(v, hasLength(12));
      expect(v.first, 100);
      expect(v.last, 400);
      for (var i = 1; i < v.length; i++) {
        expect(v[i] >= v[i - 1], isTrue);
      }
      expect(rampVolumes(first: 50, last: 50), List.filled(12, 50));
      expect(rampVolumes(first: 400, last: 100).last, 100);
      expect(rampVolumes(first: 7, last: 9, months: 1), [7]);
      expect(
        () => rampVolumes(first: -1, last: 0),
        refused(FinanceField.firstVolume),
      );
      expect(
        () => rampVolumes(first: 0, last: maxVolume + 1),
        refused(FinanceField.lastVolume),
      );
    });

    test('month by month: the first short month and the money needed', () {
      // Fictitious soap workshop: 300 000 Ar of equipment, 120 000 Ar of
      // fixed costs a month, sales growing from 100 to 400 soaps.
      final plan = cashPlan(
        startingCash: 200000,
        investment: 300000,
        volumes: rampVolumes(first: 100, last: 400),
        price: 1000,
        unitCost: 600,
        fixedMonthly: 120000,
      );
      expect(plan.months.first.revenue, 100000);
      expect(plan.months.first.costs, 180000);
      expect(plan.months.first.closing, -100000 - 80000);
      expect(plan.firstShortMonth, 0, reason: 'the equipment alone');
      expect(
        plan.firstProfitableMonth,
        plan.months.firstWhere((m) => m.net > 0).month,
      );
      expect(plan.need, -plan.lowest);
      var balance = 200000 - 300000;
      for (final m in plan.months) {
        balance += m.revenue - m.costs;
        expect(m.closing, balance);
      }
    });

    test('enough money: never short, nothing needed', () {
      final plan = cashPlan(
        startingCash: 1000000,
        investment: 0,
        volumes: List.filled(12, 500),
        price: 1000,
        unitCost: 600,
        fixedMonthly: 120000,
      );
      expect(plan.firstShortMonth, isNull);
      expect(plan.need, 0);
      expect(plan.firstProfitableMonth, 1);
      expect(plan.months.last.closing, 1000000 + 12 * 80000);
    });

    test('the largest plan does not overflow', () {
      final plan = cashPlan(
        startingCash: 0,
        investment: max,
        volumes: List.filled(12, maxVolume),
        price: 0,
        unitCost: max,
        fixedMonthly: max,
      );
      expect(plan.lowest, -max - 12 * (max + maxVolume * max));
      expect(plan.need, max + 12 * (max + maxVolume * max));
      final rich = cashPlan(
        startingCash: max,
        investment: 0,
        volumes: List.filled(12, maxVolume),
        price: max,
        unitCost: 0,
        fixedMonthly: 0,
      );
      expect(rich.months.last.closing, max + 12 * maxVolume * max);
    });

    test('refused inputs', () {
      List<int> twelve(int v) => List.filled(12, v);
      expect(
        () => cashPlan(
          startingCash: 0,
          investment: 0,
          volumes: const [],
          price: 1,
          unitCost: 0,
          fixedMonthly: 0,
        ),
        refused(FinanceField.volumes),
      );
      expect(
        () => cashPlan(
          startingCash: 0,
          investment: 0,
          volumes: List.filled(13, 1),
          price: 1,
          unitCost: 0,
          fixedMonthly: 0,
        ),
        refused(FinanceField.volumes),
      );
      expect(
        () => cashPlan(
          startingCash: -1,
          investment: 0,
          volumes: twelve(1),
          price: 1,
          unitCost: 0,
          fixedMonthly: 0,
        ),
        refused(FinanceField.startingCash),
      );
      expect(
        () => cashPlan(
          startingCash: 0,
          investment: 0,
          volumes: twelve(maxVolume + 1),
          price: 1,
          unitCost: 0,
          fixedMonthly: 0,
        ),
        refused(FinanceField.volumes),
      );
    });
  });

  group('financing', () {
    test('missing money, covered, surplus', () {
      final gap = fundingGap(need: 500000, sources: [200000, 100000]);
      expect(gap.found, 300000);
      expect(gap.missing, 200000);
      expect(gap.covered, isFalse);
      final ok = fundingGap(need: 500000, sources: [600000]);
      expect(ok.missing, 0);
      expect(ok.surplus, 100000);
      expect(ok.covered, isTrue);
      expect(fundingGap(need: 0, sources: const []).covered, isTrue);
      expect(
        () => fundingGap(need: -1, sources: const []),
        refused(FinanceField.need),
      );
      expect(
        () => fundingGap(need: 1, sources: List.filled(201, 1)),
        refused(FinanceField.sources),
      );
      expect(
        fundingGap(need: 1, sources: List.filled(200, max)).found,
        200 * max,
      );
    });

    test('months to get the investment back', () {
      expect(monthsToRecover(investment: 300000, monthlyProfit: 80000), 4);
      expect(monthsToRecover(investment: 320000, monthlyProfit: 80000), 4);
      expect(monthsToRecover(investment: 0, monthlyProfit: 1), 0);
      expect(monthsToRecover(investment: 10, monthlyProfit: 0), isNull);
      expect(monthsToRecover(investment: 10, monthlyProfit: -5), isNull);
    });
  });

  group('typed values', () {
    test('percentages', () {
      expect(parsePercentBp('30'), 3000);
      expect(parsePercentBp('12,5'), 1250);
      expect(parsePercentBp('12.25 %'), 1225);
      expect(parsePercentBp('0'), 0);
      for (final bad in ['', 'abc', '-5', '1,234', '12345']) {
        expect(parsePercentBp(bad), isNull, reason: bad);
      }
    });

    test('amounts', () {
      expect(parseAmount('15 000'), 15000);
      expect(parseAmount('15.000'), 15000);
      expect(
        parseAmount('15\u202F000'),
        15000,
        reason: 'narrow no-break space',
      );
      expect(parseAmount('0'), 0);
      expect(parseAmount('999999999999'), 999999999999);
      for (final bad in ['', '-3', '1,5', 'mille', '1000000000000']) {
        expect(parseAmount(bad), isNull, reason: bad);
      }
    });
  });
}
