import '../../finance/application/finance_service.dart';
import '../../hypotheses/domain/hypothesis_states.dart';
import 'project_synthesis.dart';

/// The nine blocks of the Business Model Canvas, in the order they are
/// usually worked out: customers and what they get first, costs last.
enum CanvasBlockKind {
  segments,
  valueProposition,
  channels,
  relationships,
  revenue,
  resources,
  activities,
  partners,
  costs,
}

/// One line of a block. Text is the user's own; numbers are computed.
sealed class CanvasEntry {
  const CanvasEntry();
}

/// A field the user wrote in a project section.
class TextEntry extends CanvasEntry {
  const TextEntry(this.text);
  final String text;
}

/// A hypothesis the user's tests validated.
class ValidatedEntry extends CanvasEntry {
  const ValidatedEntry(this.statement);
  final String statement;
}

/// The price chosen.
class PriceEntry extends CanvasEntry {
  const PriceEntry(this.priceMga);
  final int priceMga;
}

/// Units expected in the first and twelfth months.
class VolumeEntry extends CanvasEntry {
  const VolumeEntry(this.first, this.last);
  final int first;
  final int last;
}

/// An amount from "Mes chiffres" (a cost, a purchase).
class AmountEntry extends CanvasEntry {
  const AmountEntry(this.kind, this.label, this.amountMga);
  final FinanceKind kind;
  final String label;
  final int amountMga;
}

class CanvasBlock {
  const CanvasBlock(this.kind, this.entries);

  final CanvasBlockKind kind;
  final List<CanvasEntry> entries;

  bool get filled => entries.isNotEmpty;

  /// Backed by at least one validated hypothesis.
  bool get tested => entries.any((e) => e is ValidatedEntry);
}

/// Where a block is worked on: a project section, or the numbers.
sealed class CanvasSource {
  const CanvasSource();
}

class SectionSource extends CanvasSource {
  const SectionSource(this.section);
  final String section;
}

class FinanceSource extends CanvasSource {
  const FinanceSource();
}

CanvasSource sourceOf(CanvasBlockKind kind) => switch (kind) {
  CanvasBlockKind.segments => const SectionSource('customers'),
  CanvasBlockKind.valueProposition => const SectionSource('solution'),
  CanvasBlockKind.revenue || CanvasBlockKind.costs => const FinanceSource(),
  _ => const SectionSource('business_model'),
};

/// The canvas built from the work done (CLAUDE.md §16): a block holds only
/// what the user wrote, tested or counted; nothing is invented to fill it.
List<CanvasBlock> canvasOf(ProjectSynthesis s) {
  List<CanvasEntry> texts(List<(String, String)> fields) => [
    for (final (section, key) in fields)
      if (s.field(section, key) case final t?) TextEntry(t),
  ];
  List<CanvasEntry> validated(HypothesisCategory category) => [
    for (final h in s.validated(category)) ValidatedEntry(h.statement),
  ];
  final plan = s.finance.plan;
  List<CanvasEntry> amounts(FinanceKind kind) => [
    for (final i in s.finance.ofKind(kind))
      AmountEntry(kind, i.label, i.amountMga),
  ];
  return [
    CanvasBlock(CanvasBlockKind.segments, [
      ...texts([('customers', 'description'), ('customers', 'first_guess')]),
      ...validated(HypothesisCategory.customer),
    ]),
    CanvasBlock(CanvasBlockKind.valueProposition, [
      ...texts([('solution', 'first_idea'), ('solution', 'advantage')]),
      ...validated(HypothesisCategory.problem),
      ...validated(HypothesisCategory.solution),
    ]),
    CanvasBlock(CanvasBlockKind.channels, [
      ...texts([('business_model', 'channels'), ('marketing', 'channels')]),
      ...validated(HypothesisCategory.channel),
    ]),
    CanvasBlock(
      CanvasBlockKind.relationships,
      texts([('business_model', 'relationships')]),
    ),
    CanvasBlock(CanvasBlockKind.revenue, [
      if (plan.priceMga != null) PriceEntry(plan.priceMga!),
      if (s.finance.hasVolumes)
        VolumeEntry(plan.volumeFirst!, plan.volumeLast!),
      ...validated(HypothesisCategory.price),
    ]),
    CanvasBlock(CanvasBlockKind.resources, [
      ...texts([('business_model', 'resources')]),
      ...amounts(FinanceKind.investment),
    ]),
    CanvasBlock(
      CanvasBlockKind.activities,
      texts([('business_model', 'activities')]),
    ),
    CanvasBlock(
      CanvasBlockKind.partners,
      texts([('business_model', 'partners')]),
    ),
    CanvasBlock(CanvasBlockKind.costs, [
      ...amounts(FinanceKind.fixedCost),
      ...amounts(FinanceKind.variableCost),
    ]),
  ];
}
