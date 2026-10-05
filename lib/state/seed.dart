import 'dart:math' as math;

import '../budget/budget.dart';

/// The seeded monthly budget: ₹30,000.
final int seedBudgetMinor = rupees(30000);

/// The six categories from the design prototype.
final List<Category> seedCategories = List.unmodifiable([
  Category(
    id: 'food',
    name: 'Food',
    colorValue: 0xFFF2B880,
    limitMinor: rupees(6000),
  ),
  Category(
    id: 'bills',
    name: 'Bills',
    colorValue: 0xFFC7A6F2,
    limitMinor: rupees(11000),
  ),
  Category(
    id: 'travel',
    name: 'Travel',
    colorValue: 0xFF8FB8F2,
    limitMinor: rupees(3000),
  ),
  Category(
    id: 'shop',
    name: 'Shopping',
    colorValue: 0xFFF29BB8,
    limitMinor: rupees(2000),
  ),
  Category(
    id: 'fun',
    name: 'Fun',
    colorValue: 0xFF9EE6C3,
    limitMinor: rupees(1500),
  ),
  Category(
    id: 'health',
    name: 'Health',
    colorValue: 0xFFF2E28F,
    limitMinor: rupees(1500),
  ),
]);

/// The income sources offered in income mode.
const List<String> incomeSources = [
  'Salary',
  'Freelance',
  'Gift',
  'Refund',
  'Cashback',
  'Other',
];

/// The prototype's twelve expenses: (day of month, rupees, category, note).
const List<(int, int, String, String)> _prototypeExpenses = [
  (1, 8000, 'bills', 'Rent share'),
  (1, 2400, 'bills', 'Electricity and internet'),
  (1, 340, 'food', 'Lunch'),
  (1, 220, 'travel', 'Metro recharge'),
  (2, 610, 'food', 'Groceries'),
  (2, 499, 'fun', 'Movie night'),
  (3, 1850, 'shop', 'Running shoes'),
  (3, 280, 'food', 'Chai and snacks'),
  (4, 920, 'food', 'Dinner out'),
  (4, 450, 'travel', 'Cab home'),
  (5, 180, 'food', 'Breakfast'),
  (5, 650, 'health', 'Pharmacy'),
];

/// The prototype's twelve expenses, re-dated into the calendar month of [now]
/// so that they always all count toward the current month.
///
/// Each keeps its prototype day unless that day is still in the future, in
/// which case it moves back to today: day = min(prototype day, today). They
/// total ₹16,399 whatever the date. Times run from 09:00 in list order, one
/// minute apart, so the list has a stable oldest-to-newest order. Ids are
/// `seed-1` to `seed-12`.
List<Entry> seedEntries(DateTime now) => [
  for (final (i, (day, amount, categoryId, note)) in _prototypeExpenses.indexed)
    Entry(
      id: 'seed-${i + 1}',
      type: EntryType.expense,
      amountMinor: rupees(amount),
      categoryId: categoryId,
      note: note,
      occurredAt: DateTime(now.year, now.month, math.min(day, now.day), 9, i),
    ),
];
