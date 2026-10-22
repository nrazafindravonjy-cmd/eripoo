import '../../../content/formalization.dart';
import '../../finance/domain/finance_math.dart';

/// What the estimate needs to know about the company.
class CreationFeeInput {
  const CreationFeeInput({
    required this.capitalMga,
    required this.taxId,
    this.monthlyRentMga,
    this.leaseMonths,
    this.represented = false,
  });

  final int capitalMga;

  /// Kind of activity, for the synthetic tax.
  final String taxId;

  /// Set when the premises are rented under a commercial lease.
  final int? monthlyRentMga;
  final int? leaseMonths;

  /// Someone files the papers on the founder's behalf.
  final bool represented;
}

enum FeeLineKind { statutes, lease, proxy, rcs, statistics, syntheticTax }

class FeeLine {
  const FeeLine(this.kind, this.amountMga);

  final FeeLineKind kind;
  final int amountMga;
}

class FeeEstimate {
  const FeeEstimate(this.lines);

  final List<FeeLine> lines;

  int get totalMga => lines.fold(0, (sum, l) => sum + l.amountMga);
}

/// The input that the estimate refuses.
enum FeeField { capital, rent, months, tax }

class InvalidFeeInput implements Exception {
  const InvalidFeeInput(this.field);

  final FeeField field;

  @override
  String toString() => 'InvalidFeeInput(${field.name})';
}

/// Longest lease taken into account: 100 years.
const maxLeaseMonths = 1200;

/// A fee: its fixed amount, or its rate of [base] (rounded up to the
/// ariary) but never below its minimum.
int feeAmount(FeeRule rule, int base) {
  if (rule.amountMga != null) return rule.amountMga!;
  final rated = (base * rule.rateBp! + 9999) ~/ 10000;
  return rated < rule.minimumMga! ? rule.minimumMga! : rated;
}

/// The creation fees of a company as the official schedule lists them
/// (content/formalization.yaml). An estimate: the EDBM's own simulator
/// and counter are what count.
FeeEstimate estimateCreationFees(FeeSchedule fees, CreationFeeInput input) {
  if (input.capitalMga < 0 || input.capitalMga > FinanceLimits.maxAmount) {
    throw const InvalidFeeInput(FeeField.capital);
  }
  final tax = fees.syntheticTax.where((t) => t.id == input.taxId).firstOrNull;
  if (tax == null) throw const InvalidFeeInput(FeeField.tax);
  final rent = input.monthlyRentMga;
  final months = input.leaseMonths;
  if ((rent == null) != (months == null)) {
    throw InvalidFeeInput(rent == null ? FeeField.rent : FeeField.months);
  }
  if (rent != null && (rent <= 0 || rent > FinanceLimits.maxAmount)) {
    throw const InvalidFeeInput(FeeField.rent);
  }
  if (months != null && (months <= 0 || months > maxLeaseMonths)) {
    throw const InvalidFeeInput(FeeField.months);
  }
  return FeeEstimate([
    FeeLine(FeeLineKind.statutes, feeAmount(fees.statutes, input.capitalMga)),
    if (rent != null)
      FeeLine(FeeLineKind.lease, feeAmount(fees.lease, rent * months!)),
    if (input.represented) FeeLine(FeeLineKind.proxy, feeAmount(fees.proxy, 0)),
    FeeLine(FeeLineKind.rcs, feeAmount(fees.rcs, 0)),
    FeeLine(FeeLineKind.statistics, feeAmount(fees.statistics, 0)),
    FeeLine(FeeLineKind.syntheticTax, tax.amountMga),
  ]);
}
