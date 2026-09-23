/// The rule that decides whether a budget is fine, close, or blown.
///
/// Pure integer maths: no `BuildContext`, no colours and no division. Where
/// the thresholds sit is a product decision and lives here; which colour
/// paints each one is a separate decision and lives in the theme.
library;

/// How a budget is doing, in the three steps the UI paints.
enum BudgetRisk {
  /// Under 80% of the limit.
  safe,

  /// At or past 80% of the limit, but not yet at it. Amber.
  warning,

  /// At or past the limit. Red — exactly 100% counts as over, because the
  /// very next rupee is, and a customer told "on track" at their limit would
  /// be told wrong.
  over,
}

/// Where a budget turns amber, as a percentage of its limit.
const int warningPercent = 80;

/// The risk of a budget that has [spentPaise] against [limitPaise].
///
/// [spentPaise] is *spend*: `-sum(amountPaise)`, so it is positive when money
/// has left the account and negative in a category whose refunds outweighed
/// its spends. A negative spend is [BudgetRisk.safe] — nothing has been spent
/// on balance — and is never floored before the comparison.
///
/// Nothing here divides, so a limit of zero is answered rather than thrown at:
/// any spend against it is [BudgetRisk.over], and no spend against it is
/// [BudgetRisk.safe].
BudgetRisk riskFor({required int spentPaise, required int limitPaise}) {
  if (spentPaise <= 0) return BudgetRisk.safe;
  if (limitPaise <= 0) return BudgetRisk.over;
  if (spentPaise >= limitPaise) return BudgetRisk.over;
  // spentPaise / limitPaise >= 0.8, cross-multiplied.
  if (spentPaise * 100 >= limitPaise * warningPercent) {
    return BudgetRisk.warning;
  }
  return BudgetRisk.safe;
}

/// How much of the limit is used, as a fraction: `0.8` at 80%, `1.2` a fifth
/// over.
///
/// For the width of a progress bar and nothing else — every decision belongs
/// to [riskFor], which makes it in integers. A limit of zero that has been
/// spent against reads as wholly used rather than as infinity: there is no
/// fraction to report and nothing to divide by.
double ratioFor({required int spentPaise, required int limitPaise}) {
  if (spentPaise <= 0) return 0;
  if (limitPaise <= 0) return 1;
  return spentPaise / limitPaise;
}
