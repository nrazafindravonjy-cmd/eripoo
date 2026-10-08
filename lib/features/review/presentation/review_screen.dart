import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../documents/presentation/documents_providers.dart';
import '../application/review_points.dart';

/// The active project's points to review, recomputed whenever its work
/// changes. Empty when there is no project.
final reviewPointsProvider = FutureProvider<List<ReviewPoint>>((ref) async {
  final synthesis = await ref.watch(synthesisProvider.future);
  return synthesis == null ? const [] : reviewPoints(synthesis);
});

/// Where a point can be fixed.
String reviewRoute(ReviewPointKind kind) => switch (kind) {
  ReviewPointKind.priceBelowCost ||
  ReviewPointKind.priceWithoutCost ||
  ReviewPointKind.breakEvenUnreachable => AppRoutes.finances,
  ReviewPointKind.breakEvenAbovePlan => AppRoutes.cashPlan,
  ReviewPointKind.fundingMissing => AppRoutes.financing,
  ReviewPointKind.proofWithoutTest => AppRoutes.hypotheses,
  ReviewPointKind.solutionWithoutCustomers => AppRoutes.project,
};

String reviewText(BuildContext context, ReviewPoint point) {
  final l10n = AppLocalizations.of(context);
  final f = context.formatter;
  final n = point.numbers;
  return switch (point.kind) {
    ReviewPointKind.priceBelowCost => l10n.reviewPriceBelowCost(
      f.money(n[0]),
      f.money(n[1]),
    ),
    ReviewPointKind.priceWithoutCost => l10n.reviewPriceWithoutCost,
    ReviewPointKind.breakEvenUnreachable => l10n.reviewBreakEvenUnreachable,
    ReviewPointKind.breakEvenAbovePlan => l10n.reviewBreakEvenAbovePlan(
      f.integer(n[0]),
      f.integer(n[1]),
    ),
    ReviewPointKind.fundingMissing => l10n.reviewFundingMissing(f.money(n[0])),
    ReviewPointKind.proofWithoutTest => l10n.reviewProofWithoutTest,
    ReviewPointKind.solutionWithoutCustomers =>
      l10n.reviewSolutionWithoutCustomers,
  };
}

/// Inconsistencies found by fixed rules (CLAUDE.md §24: no AI where a
/// deterministic rule is enough), each with the way to look at it.
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final points = ref.watch(reviewPointsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.reviewTitle)),
      body: points.when(
        loading: () => const EripooLoadingView(),
        error: (_, _) => const EripooErrorView(),
        data: (points) => ListView(
          padding: const EdgeInsets.symmetric(vertical: EripooSpacing.lg),
          children: [
            ReadableColumn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.reviewIntro),
                  const SizedBox(height: EripooSpacing.lg),
                  if (points.isEmpty) Text(l10n.reviewNone),
                  for (final p in points) ...[
                    EripooCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.rule,
                                color: context.colors.warning.base,
                              ),
                              const SizedBox(width: EripooSpacing.md),
                              Expanded(child: Text(reviewText(context, p))),
                            ],
                          ),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: EripooButton(
                              label: l10n.reviewOpen,
                              variant: EripooButtonVariant.tertiary,
                              onPressed: () => context.go(reviewRoute(p.kind)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: EripooSpacing.sm),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
