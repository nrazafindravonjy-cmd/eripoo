import '../../documents/application/project_synthesis.dart';
import '../../hypotheses/domain/hypothesis_states.dart';

/// What a point to review is about (CLAUDE.md §24: inconsistencies are
/// found by fixed rules, not by an AI model).
enum ReviewPointKind {
  /// The price is below what one unit costs.
  priceBelowCost,

  /// A price is set while no unit cost is written down.
  priceWithoutCost,

  /// At this price, no number of sales covers the month's costs.
  breakEvenUnreachable,

  /// Covering the month's costs needs more sales than planned by month 12.
  breakEvenAbovePlan,

  /// The money found does not cover what the cash plan needs.
  fundingMissing,

  /// The pitch cites a proof while no hypothesis is validated yet.
  proofWithoutTest,

  /// A solution is described before anyone it is for.
  solutionWithoutCustomers,
}

/// One point, with the numbers it was computed from (whole ariary or
/// units), so the screen can say exactly why.
class ReviewPoint {
  const ReviewPoint(this.kind, [this.numbers = const []]);

  final ReviewPointKind kind;
  final List<int> numbers;
}

/// Everything that looks inconsistent in the user's own work, in the order
/// worth fixing. Each rule is deterministic and explained to the user; a
/// point is a question to look at, never a verdict.
List<ReviewPoint> reviewPoints(ProjectSynthesis s) {
  final f = s.finance;
  final price = f.plan.priceMga;
  final points = <ReviewPoint>[];

  if (price != null && !f.hasUnitCost) {
    points.add(const ReviewPoint(ReviewPointKind.priceWithoutCost));
  }
  final margin = f.unitMargin;
  if (f.hasUnitCost && margin != null && margin.isLoss) {
    points.add(
      ReviewPoint(ReviewPointKind.priceBelowCost, [price!, f.unitCost]),
    );
  }
  final breakEven = f.breakEvenPoint;
  if (breakEven != null && f.hasUnitCost && !margin!.isLoss) {
    if (!breakEven.reachable) {
      points.add(const ReviewPoint(ReviewPointKind.breakEvenUnreachable));
    } else if (f.hasVolumes && breakEven.units! > f.plan.volumeLast!) {
      points.add(
        ReviewPoint(ReviewPointKind.breakEvenAbovePlan, [
          breakEven.units!,
          f.plan.volumeLast!,
        ]),
      );
    }
  }
  final gap = f.gap;
  if (gap != null && gap.missing > 0) {
    points.add(ReviewPoint(ReviewPointKind.fundingMissing, [gap.missing]));
  }

  if (s.field('pitch', 'proof') != null && s.validated().isEmpty) {
    points.add(const ReviewPoint(ReviewPointKind.proofWithoutTest));
  }
  final forWhom =
      s.field('customers', 'description') ??
      s.field('customers', 'first_guess');
  if (s.field('solution', 'first_idea') != null &&
      forWhom == null &&
      s.validated(HypothesisCategory.customer).isEmpty) {
    points.add(const ReviewPoint(ReviewPointKind.solutionWithoutCustomers));
  }
  return points;
}
