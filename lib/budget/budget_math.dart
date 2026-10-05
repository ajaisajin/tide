/// The budget-status rules as small pure functions. Pure Dart: imports nothing
/// from Flutter.
///
/// Dates: an entry belongs to the calendar month named by the `year` and
/// `month` fields of its `occurredAt`, compared as they stand with those of
/// `now`. No time-zone conversion is done, so pass local times for both.
library;

import 'models.dart';
import 'money.dart';

/// True when [occurredAt] falls in the same calendar month as [now].
bool isInMonth(DateTime occurredAt, DateTime now) =>
    occurredAt.year == now.year && occurredAt.month == now.month;

/// The entries dated in the calendar month of [now], in their original order.
List<Entry> entriesInMonth(Iterable<Entry> entries, DateTime now) => [
  for (final e in entries)
    if (isInMonth(e.occurredAt, now)) e,
];

/// Amount available and remaining for the calendar month of [now].
MonthlyPosition monthlyPosition({
  required int budgetMinor,
  required Iterable<Entry> entries,
  required DateTime now,
}) {
  var income = 0;
  var spent = 0;
  for (final e in entries) {
    if (!isInMonth(e.occurredAt, now)) continue;
    switch (e.type) {
      case EntryType.income:
        income += e.amountMinor;
      case EntryType.expense:
        spent += e.amountMinor;
    }
  }
  return MonthlyPosition(
    budgetMinor: budgetMinor,
    incomeMinor: income,
    spentMinor: spent,
  );
}

/// Remaining divided by available, between 0 and 1. It is 0 when nothing
/// remains, when the month is overspent, or when nothing was available.
double fillLevel({required int remainingMinor, required int availableMinor}) {
  if (remainingMinor <= 0 || availableMinor <= 0) return 0;
  final level = remainingMinor / availableMinor;
  return level > 1 ? 1 : level;
}

/// The status band for a month.
///
/// The boundaries are decided on the integer amounts, not on a rounded ratio:
/// above half is "Calm water", above a quarter and at most half is "Running
/// lower", at most a quarter with nothing owed is "Nearly dry", and a negative
/// remainder is "Below the line". A month with nothing available and nothing
/// spent is "Nearly dry".
StatusBand statusBand({
  required int remainingMinor,
  required int availableMinor,
}) {
  if (remainingMinor < 0) return StatusBand.belowTheLine;
  if (remainingMinor == 0 || availableMinor <= 0) return StatusBand.nearlyDry;
  if (remainingMinor * 2 > availableMinor) return StatusBand.calmWater;
  if (remainingMinor * 4 > availableMinor) return StatusBand.runningLower;
  return StatusBand.nearlyDry;
}

/// The number of days in the calendar month of [date].
int daysInMonth(DateTime date) => DateTime(date.year, date.month + 1, 0).day;

/// Days left in the month of [now], counting today. Always at least 1.
int daysLeftInMonth(DateTime now) => daysInMonth(now) - now.day + 1;

/// Remaining divided by the days left counting today, rounded down to a whole
/// rupee and returned in paise. It is 0 when nothing remains.
int safeToSpendToday({required int remainingMinor, required DateTime now}) {
  if (remainingMinor <= 0) return 0;
  final perDay = remainingMinor ~/ daysLeftInMonth(now);
  return perDay - perDay % paisePerRupee;
}

/// One position per category, in the order given, from the expenses dated in
/// the calendar month of [now].
///
/// Income never counts toward a category, even if it carries a category id.
/// An expense with no category, or one that names an unknown category, still
/// counts toward the month's total but appears in no category.
List<CategoryPosition> categoryPositions({
  required Iterable<Entry> entries,
  required Iterable<Category> categories,
  required DateTime now,
}) {
  final spent = <String, int>{};
  for (final e in entries) {
    final id = e.categoryId;
    if (id == null || !e.isExpense || !isInMonth(e.occurredAt, now)) continue;
    spent[id] = (spent[id] ?? 0) + e.amountMinor;
  }
  return [
    for (final c in categories)
      CategoryPosition(category: c, spentMinor: spent[c.id] ?? 0),
  ];
}

/// Everything the screens need for the calendar month of [now].
BudgetSnapshot budgetSnapshot({
  required int budgetMinor,
  required Iterable<Entry> entries,
  required Iterable<Category> categories,
  required DateTime now,
}) {
  final position = monthlyPosition(
    budgetMinor: budgetMinor,
    entries: entries,
    now: now,
  );
  return BudgetSnapshot(
    now: now,
    position: position,
    fillLevel: fillLevel(
      remainingMinor: position.remainingMinor,
      availableMinor: position.availableMinor,
    ),
    band: statusBand(
      remainingMinor: position.remainingMinor,
      availableMinor: position.availableMinor,
    ),
    daysLeft: daysLeftInMonth(now),
    safeToSpendTodayMinor: safeToSpendToday(
      remainingMinor: position.remainingMinor,
      now: now,
    ),
    categories: categoryPositions(
      entries: entries,
      categories: categories,
      now: now,
    ),
  );
}
