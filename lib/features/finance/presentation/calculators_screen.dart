import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../content/content_pack.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../quest/presentation/content_widgets.dart';
import '../../quest/presentation/journey_providers.dart';
import '../../tools/application/competitor_service.dart';
import '../../tools/presentation/tools_providers.dart';
import '../application/finance_service.dart';
import '../domain/finance_math.dart';
import 'finance_providers.dart';
import 'finances_screen.dart';

/// A calculator: the tool's help from content, fields pre-filled with the
/// project's numbers (free to change, to try), and the result in words.
/// Nothing is saved unless the user asks.
abstract class _CalculatorState<T extends ConsumerStatefulWidget>
    extends ConsumerState<T> {
  ToolKind get kind;

  /// Field keys, in order.
  List<String> get keys;
  String label(AppLocalizations l10n, String key);

  /// Initial text of a field from the project's numbers.
  int? initial(FinanceSnapshot s, String key);

  /// Percent fields; the others are ariary amounts.
  bool isPercent(String key) => false;

  List<Widget> results(BuildContext context, Map<String, int> values);

  final _controllers = <String, TextEditingController>{};

  /// Fields the user typed in: no longer follow the project's numbers.
  final _touched = <String>{};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controller(String key) =>
      _controllers.putIfAbsent(key, TextEditingController.new);

  int? _parse(String key) {
    final text = _controller(key).text;
    return isPercent(key) ? parsePercentBp(text) : parseAmount(text);
  }

  String? projectId() => ref.read(activeProjectProvider).value?.id;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pack = ref.watch(contentPackProvider);
    final tool = pack.tools.where((t) => t.kind == kind).firstOrNull;
    final project = ref.watch(activeProjectProvider).value;
    final snapshot = project == null
        ? null
        : ref.watch(financeSnapshotProvider(project.id)).value;
    if (snapshot != null) {
      for (final key in keys) {
        if (_touched.contains(key)) continue;
        final value = initial(snapshot, key);
        final text = value == null
            ? ''
            : (isPercent(key) ? (value ~/ 100).toString() : value.toString());
        if (_controller(key).text != text) _controller(key).text = text;
      }
    }
    final values = <String, int>{};
    var invalid = false;
    for (final key in keys) {
      if (_controller(key).text.trim().isEmpty) continue;
      final v = _parse(key);
      if (v == null) {
        invalid = true;
      } else {
        values[key] = v;
      }
    }
    List<Widget> shown;
    try {
      shown = invalid || values.length < keys.length
          ? [Text(l10n.calcFillIn)]
          : results(context, values);
    } on InvalidFinanceInput {
      shown = [Text(l10n.calcInvalid)];
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tool == null ? l10n.financeTitle : contentText(context, tool.title),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
        children: [
          ReadableColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (tool != null)
                  for (final h in tool.help) ...[
                    Text(contentText(context, h)),
                    const SizedBox(height: EripooSpacing.sm),
                  ],
                if (snapshot != null)
                  Text(
                    l10n.calcFromProject,
                    style: context.textStyles.bodySmall,
                  ),
                for (final key in keys) ...[
                  const SizedBox(height: EripooSpacing.md),
                  EripooTextField(
                    label: label(l10n, key),
                    controller: _controller(key),
                    keyboardType: isPercent(key)
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.number,
                    errorText:
                        _controller(key).text.trim().isNotEmpty &&
                            _parse(key) == null
                        ? l10n.calcInvalid
                        : null,
                    onChanged: (_) => setState(() => _touched.add(key)),
                  ),
                ],
                const SizedBox(height: EripooSpacing.lg),
                Semantics(
                  liveRegion: true,
                  child: EripooCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: shown,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Price from the cost and the share of the price to keep.
class PriceCalculatorScreen extends ConsumerStatefulWidget {
  const PriceCalculatorScreen({super.key});

  @override
  ConsumerState<PriceCalculatorScreen> createState() => _PriceState();
}

class _PriceState extends _CalculatorState<PriceCalculatorScreen> {
  @override
  ToolKind get kind => ToolKind.priceCalculator;
  @override
  List<String> get keys => const ['cost', 'margin'];
  @override
  bool isPercent(String key) => key == 'margin';
  @override
  String label(AppLocalizations l10n, String key) =>
      key == 'cost' ? l10n.calcUnitCostLabel : l10n.calcMarginLabel;
  @override
  int? initial(FinanceSnapshot s, String key) =>
      key == 'cost' && s.hasUnitCost ? s.unitCost : null;

  @override
  List<Widget> results(BuildContext context, Map<String, int> values) {
    final l10n = AppLocalizations.of(context);
    final f = context.formatter;
    final p = suggestPrice(
      unitCost: values['cost']!,
      marginBp: values['margin']!,
    );
    final project = ref.watch(activeProjectProvider).value;
    final competitorPrices = project == null
        ? const <int>[]
        : <int>[
            for (final c
                in ref.watch(competitorsProvider(project.id)).value ??
                    const <Competitor>[])
              if (c.priceMga != null) c.priceMga!,
          ];
    final range = PriceRange.of(competitorPrices);
    return [
      Text(
        l10n.calcPriceResult(f.money(p.price)),
        style: context.textStyles.titleMedium,
      ),
      const SizedBox(height: EripooSpacing.xs),
      Text(
        p.markupBp == null
            ? l10n.calcPriceExplainNoCost(f.money(p.unitMargin))
            : l10n.calcPriceExplain(
                f.money(p.unitMargin),
                f.percentBp(p.markupBp!),
              ),
      ),
      if (range != null) ...[
        const SizedBox(height: EripooSpacing.sm),
        Text(
          l10n.calcCompetitors(
            f.money(range.low),
            f.money(range.high),
            f.money(range.median),
          ),
        ),
        Text(switch (range.position(p.price)) {
          -1 => l10n.calcCompetitorsBelow,
          1 => l10n.calcCompetitorsAbove,
          _ => l10n.calcCompetitorsInside,
        }),
      ],
      if (project != null) ...[
        const SizedBox(height: EripooSpacing.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: EripooButton(
            label: l10n.calcUsePrice,
            icon: Icons.check,
            variant: EripooButtonVariant.secondary,
            onPressed: () => _usePrice(project.id, p.price),
          ),
        ),
      ],
    ];
  }

  Future<void> _usePrice(String projectId, int price) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(financeServiceProvider);
    final plan = await service.planOf(projectId);
    await service.savePlan(
      projectId,
      priceMga: price,
      volumeFirst: plan.volumeFirst,
      volumeLast: plan.volumeLast,
    );
    messenger.showSnackBar(SnackBar(content: Text(l10n.calcPriceSaved)));
  }
}

/// What is left on one unit, as an amount and two different rates.
class MarginCalculatorScreen extends ConsumerStatefulWidget {
  const MarginCalculatorScreen({super.key});

  @override
  ConsumerState<MarginCalculatorScreen> createState() => _MarginState();
}

class _MarginState extends _CalculatorState<MarginCalculatorScreen> {
  @override
  ToolKind get kind => ToolKind.marginCalculator;
  @override
  List<String> get keys => const ['price', 'cost'];
  @override
  String label(AppLocalizations l10n, String key) =>
      key == 'price' ? l10n.calcPriceLabel : l10n.calcUnitCostLabel;
  @override
  int? initial(FinanceSnapshot s, String key) =>
      key == 'price' ? s.plan.priceMga : (s.hasUnitCost ? s.unitCost : null);

  @override
  List<Widget> results(BuildContext context, Map<String, int> values) {
    final l10n = AppLocalizations.of(context);
    final f = context.formatter;
    final m = margin(price: values['price']!, unitCost: values['cost']!);
    return [
      Text(
        m.isLoss
            ? l10n.financeMarginLoss(f.money(-m.unitMargin))
            : l10n.calcMarginResult(f.money(m.unitMargin)),
        style: context.textStyles.titleMedium,
      ),
      if (m.marginBp != null && m.markupBp != null) ...[
        const SizedBox(height: EripooSpacing.xs),
        Text(
          l10n.calcMarginRates(
            f.percentBp(m.marginBp!),
            f.percentBp(m.markupBp!),
          ),
        ),
      ],
    ];
  }
}

/// Units to sell each month to pay the month's fixed costs.
class BreakEvenCalculatorScreen extends ConsumerStatefulWidget {
  const BreakEvenCalculatorScreen({super.key});

  @override
  ConsumerState<BreakEvenCalculatorScreen> createState() => _BreakEvenState();
}

class _BreakEvenState extends _CalculatorState<BreakEvenCalculatorScreen> {
  @override
  ToolKind get kind => ToolKind.breakEvenCalculator;
  @override
  List<String> get keys => const ['fixed', 'price', 'cost'];
  @override
  String label(AppLocalizations l10n, String key) => switch (key) {
    'fixed' => l10n.calcFixedLabel,
    'price' => l10n.calcPriceLabel,
    _ => l10n.calcUnitCostLabel,
  };
  @override
  int? initial(FinanceSnapshot s, String key) => switch (key) {
    'fixed' => s.ofKind(FinanceKind.fixedCost).isEmpty ? null : s.fixedMonthly,
    'price' => s.plan.priceMga,
    _ => s.hasUnitCost ? s.unitCost : null,
  };

  @override
  List<Widget> results(BuildContext context, Map<String, int> values) {
    final l10n = AppLocalizations.of(context);
    final f = context.formatter;
    final b = breakEven(
      fixedMonthly: values['fixed']!,
      price: values['price']!,
      unitCost: values['cost']!,
    );
    return [
      Text(
        breakEvenSentence(l10n, f, b),
        style: context.textStyles.titleMedium,
      ),
      if (b.reachable && !b.beyondLimits && b.units! > 0) ...[
        const SizedBox(height: EripooSpacing.xs),
        Text(l10n.calcPerDay(f.integer((b.units! + 29) ~/ 30))),
      ],
    ];
  }
}
