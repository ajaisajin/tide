/// The rules for choosing a budget: default category limits, which budget a
/// month uses, how the setup vessel's level maps to an amount, and which
/// typed amounts are accepted. Pure Dart: imports nothing from Flutter.
library;

import 'money.dart';
import 'year_month.dart';

// ---------------------------------------------------------------------------
// Default category limits
// ---------------------------------------------------------------------------

/// Each default category's share of the budget, in whole percent, keyed by
/// category id and in display order.
const Map<String, int> defaultLimitSharePercent = {
  'food': 20,
  'bills': 35,
  'travel': 10,
  'shop': 7,
  'fun': 5,
  'health': 5,
};

/// Category limits are whole multiples of this: ₹100, in paise.
const int limitRoundingMinor = 100 * paisePerRupee;

/// The smallest default limit a category is given: ₹100, in paise.
const int minDefaultLimitMinor = 100 * paisePerRupee;

/// The default limit for each category, in paise, keyed by category id, for a
/// budget of [budgetMinor].
///
/// Each is the category's share of the budget rounded down to a multiple of
/// ₹100, and never less than ₹100. The limits need not add up to the budget.
Map<String, int> defaultCategoryLimits(int budgetMinor) {
  final budget = budgetMinor < 0 ? 0 : budgetMinor;
  return {
    for (final MapEntry(key: id, value: percent)
        in defaultLimitSharePercent.entries)
      id: _defaultLimit(budget, percent),
  };
}

int _defaultLimit(int budgetMinor, int percent) {
  final share = budgetMinor * percent ~/ 100;
  final rounded = share - share % limitRoundingMinor;
  return rounded < minDefaultLimitMinor ? minDefaultLimitMinor : rounded;
}

// ---------------------------------------------------------------------------
// One budget per month, carried forward
// ---------------------------------------------------------------------------

/// The budget in force for [month], in paise, given the budgets that have
/// been set: that month's own if it has one, otherwise the one set for the
/// most recent earlier month. Null when no budget was set in or before
/// [month]; a budget set for a later month never applies backwards.
int? effectiveBudgetMinor(Map<YearMonth, int> budgets, YearMonth month) {
  YearMonth? best;
  for (final candidate in budgets.keys) {
    if (candidate.isAfter(month)) continue;
    if (best == null || candidate.isAfter(best)) best = candidate;
  }
  return best == null ? null : budgets[best];
}

// ---------------------------------------------------------------------------
// Setting the budget by filling the vessel
// ---------------------------------------------------------------------------

/// Incomes below this (₹10,000, in paise) use the small step.
const int smallIncomeThresholdMinor = 10000 * paisePerRupee;

/// The step for incomes of ₹10,000 or more: ₹500, in paise.
const int budgetStepLargeMinor = 500 * paisePerRupee;

/// The step for incomes below ₹10,000: ₹100, in paise.
const int budgetStepSmallMinor = 100 * paisePerRupee;

/// The size of one step of the budget vessel for [incomeMinor]: ₹500, or ₹100
/// when income is below ₹10,000. In paise.
int budgetStepMinor(int incomeMinor) => incomeMinor < smallIncomeThresholdMinor
    ? budgetStepSmallMinor
    : budgetStepLargeMinor;

/// The budget, in paise, that a vessel filled to [level] stands for.
///
/// [level] is the share of the vessel that is full, 0 to 1; values outside
/// that range (a drag past the top or bottom) count as the nearest end. The
/// result is that share of [incomeMinor] rounded to the nearest step, and
/// never less than ₹0 or more than the income. A full vessel is exactly the
/// income even when the income is not a whole number of steps.
int budgetForLevel({required double level, required int incomeMinor}) {
  if (incomeMinor <= 0 || level.isNaN || level <= 0) return 0;
  if (level >= 1) return incomeMinor;
  final step = budgetStepMinor(incomeMinor);
  final snapped = (level * incomeMinor / step).round() * step;
  return snapped > incomeMinor ? incomeMinor : snapped;
}

/// The level, 0 to 1, at which the vessel shows [budgetMinor] out of
/// [incomeMinor]. The inverse of [budgetForLevel] for any budget on a step,
/// and also defined for typed budgets between steps. 0 when there is no
/// income.
double levelForBudget({required int budgetMinor, required int incomeMinor}) {
  if (incomeMinor <= 0 || budgetMinor <= 0) return 0;
  if (budgetMinor >= incomeMinor) return 1;
  return budgetMinor / incomeMinor;
}

/// The budget one step above [budgetMinor]: the next multiple of the step,
/// or the income if that is nearer. A typed budget between steps moves up to
/// the next step, so ₹28,750 becomes ₹29,000.
int stepBudgetUp({required int budgetMinor, required int incomeMinor}) {
  if (incomeMinor <= 0) return 0;
  if (budgetMinor < 0) return 0;
  if (budgetMinor >= incomeMinor) return incomeMinor;
  final step = budgetStepMinor(incomeMinor);
  final next = (budgetMinor ~/ step + 1) * step;
  return next > incomeMinor ? incomeMinor : next;
}

/// The budget one step below [budgetMinor]: the next lower multiple of the
/// step, never below ₹0. A typed budget between steps moves down to the step
/// below it, so ₹28,750 becomes ₹28,500.
int stepBudgetDown({required int budgetMinor, required int incomeMinor}) {
  if (incomeMinor <= 0 || budgetMinor <= 0) return 0;
  final from = budgetMinor > incomeMinor ? incomeMinor : budgetMinor;
  final step = budgetStepMinor(incomeMinor);
  final below = (from - 1) ~/ step * step;
  return below < 0 ? 0 : below;
}

// ---------------------------------------------------------------------------
// Typed amounts
// ---------------------------------------------------------------------------

/// The smallest income, budget or category limit: ₹1, in paise.
const int minAmountMinor = 1 * paisePerRupee;

/// The largest income or category limit: ₹99,99,999, in paise.
const int maxAmountMinor = 9999999 * paisePerRupee;

/// Why an income or a category limit is or is not acceptable.
enum AmountCheck {
  ok,

  /// Less than ₹1.
  belowMinimum,

  /// More than ₹99,99,999.
  aboveMaximum,

  /// Has paise left over; only whole rupees are accepted.
  notWholeRupees;

  bool get isOk => this == AmountCheck.ok;
}

/// Checks a monthly income, in paise: a whole number of rupees from ₹1 to
/// ₹99,99,999.
AmountCheck checkIncome(int incomeMinor) => _checkAmount(incomeMinor);

/// Checks a category limit, in paise: a whole number of rupees from ₹1 to
/// ₹99,99,999.
AmountCheck checkCategoryLimit(int limitMinor) => _checkAmount(limitMinor);

AmountCheck _checkAmount(int amountMinor) {
  if (amountMinor < minAmountMinor) return AmountCheck.belowMinimum;
  if (amountMinor > maxAmountMinor) return AmountCheck.aboveMaximum;
  if (amountMinor % paisePerRupee != 0) return AmountCheck.notWholeRupees;
  return AmountCheck.ok;
}

/// Why a typed budget is or is not acceptable.
enum BudgetCheck {
  ok,

  /// Less than ₹1.
  belowMinimum,

  /// More than the income.
  aboveIncome,

  /// Has paise left over; only whole rupees are accepted.
  notWholeRupees;

  bool get isOk => this == BudgetCheck.ok;
}

/// Checks a typed budget, in paise: a whole number of rupees from ₹1 up to
/// [incomeMinor]. Unlike the vessel, typing is not held to the step size.
BudgetCheck checkTypedBudget({
  required int budgetMinor,
  required int incomeMinor,
}) {
  if (budgetMinor < minAmountMinor) return BudgetCheck.belowMinimum;
  if (budgetMinor > incomeMinor) return BudgetCheck.aboveIncome;
  if (budgetMinor % paisePerRupee != 0) return BudgetCheck.notWholeRupees;
  return BudgetCheck.ok;
}

// ---------------------------------------------------------------------------
// Category limits against the budget
// ---------------------------------------------------------------------------

/// The total of the category limits set beside the budget.
class LimitsComparison {
  const LimitsComparison({required this.totalMinor, required this.budgetMinor});

  /// The sum of every category's limit, in paise.
  final int totalMinor;

  final int budgetMinor;

  /// True when the limits add up to more than the budget.
  bool get isOverBudget => totalMinor > budgetMinor;

  /// How far the limits exceed the budget, in paise. 0 when they do not.
  int get overByMinor => isOverBudget ? totalMinor - budgetMinor : 0;

  /// How much of the budget no limit covers, in paise. 0 when the limits
  /// reach or exceed the budget.
  int get unallocatedMinor => isOverBudget ? 0 : budgetMinor - totalMinor;

  @override
  bool operator ==(Object other) =>
      other is LimitsComparison &&
      other.totalMinor == totalMinor &&
      other.budgetMinor == budgetMinor;

  @override
  int get hashCode => Object.hash(totalMinor, budgetMinor);

  @override
  String toString() => 'LimitsComparison(total $totalMinor of $budgetMinor)';
}

/// Adds up [limitsMinor] and sets the total beside [budgetMinor].
LimitsComparison compareLimitsWithBudget({
  required Iterable<int> limitsMinor,
  required int budgetMinor,
}) {
  var total = 0;
  for (final limit in limitsMinor) {
    total += limit;
  }
  return LimitsComparison(totalMinor: total, budgetMinor: budgetMinor);
}
