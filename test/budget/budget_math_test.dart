import 'package:flutter_test/flutter_test.dart';
import 'package:tide/budget/budget.dart';

var _nextId = 0;

Entry expense(int wholeRupees, DateTime at, {String? category = 'food'}) =>
    Entry(
      id: 'x${_nextId++}',
      type: EntryType.expense,
      amountMinor: rupees(wholeRupees),
      categoryId: category,
      occurredAt: at,
    );

Entry income(int wholeRupees, DateTime at, {String? category}) => Entry(
  id: 'i${_nextId++}',
  type: EntryType.income,
  amountMinor: rupees(wholeRupees),
  categoryId: category,
  note: 'Salary',
  occurredAt: at,
);

Category category(String id, int limitRupees) => Category(
  id: id,
  name: id,
  colorValue: 0xFF000000,
  limitMinor: rupees(limitRupees),
);

void main() {
  final oct5 = DateTime(2026, 10, 5, 14, 30);
  final budget = rupees(30000);

  group('Monthly position', () {
    test('Expenses only', () {
      final p = monthlyPosition(
        budgetMinor: budget,
        entries: [expense(16000, oct5), expense(399, DateTime(2026, 10, 1))],
        now: oct5,
      );
      expect(p.availableMinor, rupees(30000));
      expect(p.remainingMinor, rupees(13601));
    });

    test('Income raises the amount available', () {
      final p = monthlyPosition(
        budgetMinor: budget,
        entries: [expense(16399, oct5), income(5000, DateTime(2026, 10, 3))],
        now: oct5,
      );
      expect(p.availableMinor, rupees(35000));
      expect(p.remainingMinor, rupees(18601));
    });

    test('Entry from another month', () {
      final before = monthlyPosition(
        budgetMinor: budget,
        entries: [expense(16399, oct5)],
        now: oct5,
      );
      final after = monthlyPosition(
        budgetMinor: budget,
        entries: [
          expense(16399, oct5),
          expense(4000, DateTime(2026, 9, 28)),
          income(9000, DateTime(2026, 9, 30)),
          expense(700, DateTime(2026, 11, 1)),
          // Same month number, different year.
          expense(1200, DateTime(2025, 10, 5)),
        ],
        now: oct5,
      );
      expect(after, before);
      expect(after.remainingMinor, rupees(13601));
    });

    test('month edges: 23:59:59 on the last day and 00:00 on the first', () {
      final entries = [
        expense(100, DateTime(2026, 10, 1)), // 00:00 on the 1st: in
        expense(200, DateTime(2026, 10, 31, 23, 59, 59)), // last second: in
        expense(400, DateTime(2026, 9, 30, 23, 59, 59)), // previous month
        expense(800, DateTime(2026, 11, 1)), // 00:00 next month
      ];
      final p = monthlyPosition(
        budgetMinor: budget,
        entries: entries,
        now: oct5,
      );
      expect(p.spentMinor, rupees(300));
      expect(entriesInMonth(entries, oct5), entries.sublist(0, 2));
    });

    test('zero budget', () {
      final empty = budgetSnapshot(
        budgetMinor: 0,
        entries: const [],
        categories: const [],
        now: oct5,
      );
      expect(empty.availableMinor, 0);
      expect(empty.remainingMinor, 0);
      expect(empty.fillLevel, 0);
      expect(empty.band, StatusBand.nearlyDry);
      expect(empty.safeToSpendTodayMinor, 0);

      final spent = budgetSnapshot(
        budgetMinor: 0,
        entries: [expense(50, oct5)],
        categories: const [],
        now: oct5,
      );
      expect(spent.remainingMinor, rupees(-50));
      expect(spent.fillLevel, 0);
      expect(spent.band, StatusBand.belowTheLine);
      expect(spent.safeToSpendTodayMinor, 0);

      final funded = budgetSnapshot(
        budgetMinor: 0,
        entries: [income(1000, oct5)],
        categories: const [],
        now: oct5,
      );
      expect(funded.availableMinor, rupees(1000));
      expect(funded.fillLevel, 1);
      expect(funded.band, StatusBand.calmWater);
    });
  });

  group('Fill level', () {
    test('Part of the budget is left', () {
      final level = fillLevel(
        remainingMinor: rupees(13601),
        availableMinor: rupees(30000),
      );
      expect(level.toStringAsFixed(2), '0.45');
      expect(level, closeTo(0.4534, 0.0001));
    });

    test('Overspent month', () {
      expect(
        fillLevel(remainingMinor: rupees(-2000), availableMinor: rupees(30000)),
        0,
      );
    });

    test('zero remaining, zero available, and full', () {
      expect(fillLevel(remainingMinor: 0, availableMinor: rupees(30000)), 0);
      expect(fillLevel(remainingMinor: 0, availableMinor: 0), 0);
      expect(
        fillLevel(remainingMinor: rupees(30000), availableMinor: rupees(30000)),
        1,
      );
    });
  });

  group('Status band', () {
    StatusBand band(int remainingRupees, [int availableRupees = 30000]) =>
        statusBand(
          remainingMinor: rupees(remainingRupees),
          availableMinor: rupees(availableRupees),
        );

    test('Above half', () {
      // 18,600 of 30,000 is a fill level of 0.62.
      expect(band(18600), StatusBand.calmWater);
      expect(band(18600).label, 'Calm water');
    });

    test('Exactly half', () {
      expect(band(15000), StatusBand.runningLower);
      expect(band(15000).label, 'Running lower');
      // One paisa above half is calm water.
      expect(
        statusBand(remainingMinor: 1500001, availableMinor: 3000000),
        StatusBand.calmWater,
      );
    });

    test('Exactly nothing left', () {
      expect(band(0), StatusBand.nearlyDry);
      expect(band(0).label, 'Nearly dry');
    });

    test('Overspent', () {
      expect(band(-2000), StatusBand.belowTheLine);
      expect(band(-2000).label, 'Below the line');
      // One paisa under is already below the line.
      expect(
        statusBand(remainingMinor: -1, availableMinor: 3000000),
        StatusBand.belowTheLine,
      );
    });

    test('quarter boundary: exactly 0.25 is nearly dry, just above is not', () {
      expect(band(7500), StatusBand.nearlyDry);
      expect(
        statusBand(remainingMinor: 750001, availableMinor: 3000000),
        StatusBand.runningLower,
      );
      expect(band(13601), StatusBand.runningLower);
    });
  });

  group('Safe to spend today', () {
    test('Mid-month', () {
      expect(daysLeftInMonth(DateTime(2026, 10, 5)), 27);
      expect(
        safeToSpendToday(remainingMinor: rupees(13601), now: oct5),
        rupees(503),
      );
    });

    test('Last day of the month', () {
      final oct31 = DateTime(2026, 10, 31, 22);
      expect(daysLeftInMonth(oct31), 1);
      expect(
        safeToSpendToday(remainingMinor: rupees(800), now: oct31),
        rupees(800),
      );
    });

    test('Overspent', () {
      expect(safeToSpendToday(remainingMinor: rupees(-2000), now: oct5), 0);
      expect(safeToSpendToday(remainingMinor: 0, now: oct5), 0);
    });

    test('rounds down to a whole rupee, never up', () {
      // ₹100 over 27 days is ₹3.70 a day.
      expect(
        safeToSpendToday(remainingMinor: rupees(100), now: oct5),
        rupees(3),
      );
      // ₹20 over 27 days is under a rupee a day.
      expect(safeToSpendToday(remainingMinor: rupees(20), now: oct5), 0);
    });

    test('days left in February, leap and common years', () {
      expect(daysInMonth(DateTime(2028, 2, 10)), 29);
      expect(daysLeftInMonth(DateTime(2028, 2, 1)), 29);
      expect(daysLeftInMonth(DateTime(2028, 2, 10)), 20);
      expect(daysLeftInMonth(DateTime(2028, 2, 29)), 1);
      expect(daysInMonth(DateTime(2026, 2, 10)), 28);
      expect(daysLeftInMonth(DateTime(2026, 2, 28)), 1);
      // December does not spill into the next year.
      expect(daysLeftInMonth(DateTime(2026, 12, 1)), 31);
      expect(
        safeToSpendToday(
          remainingMinor: rupees(2900),
          now: DateTime(2028, 2, 1),
        ),
        rupees(100),
      );
    });
  });

  group('Category position', () {
    final food = category('food', 6000);
    final shop = category('shop', 2000);

    List<CategoryPosition> positions(List<Entry> entries) => categoryPositions(
      entries: entries,
      categories: [food, shop],
      now: oct5,
    );

    test('Within the limit', () {
      final p = positions([
        for (final amount in [340, 610, 280, 920, 180]) expense(amount, oct5),
      ]).first;
      expect(p.category, food);
      expect(p.spentMinor, rupees(2330));
      expect(p.sharePercent, 39);
      expect(p.share, closeTo(0.3883, 0.0001));
      expect(p.nearLimit, isFalse);
      expect(p.overLimit, isFalse);
      expect(p.leftMinor, rupees(3670));
    });

    test('Near the limit', () {
      final p = positions([expense(1850, oct5, category: 'shop')]).last;
      expect(p.spentMinor, rupees(1850));
      expect(p.nearLimit, isTrue);
      expect(p.overLimit, isFalse);
    });

    test('Limit reached', () {
      final p = positions([expense(2000, oct5, category: 'shop')]).last;
      expect(p.sharePercent, 100);
      expect(p.overLimit, isTrue);
      expect(p.nearLimit, isFalse);
    });

    test('Income is not category spend', () {
      final entries = [
        expense(340, oct5),
        expense(1850, oct5, category: 'shop'),
      ];
      final before = positions(entries);
      final after = positions([
        ...entries,
        income(5000, oct5),
        // Even an income entry that carries a category id is ignored.
        income(700, oct5, category: 'food'),
      ]);
      expect(after, before);
    });

    test('flag boundaries use exact amounts, not the rounded percentage', () {
      CategoryPosition at(int paise) =>
          CategoryPosition(category: shop, spentMinor: paise);
      expect(at(159999).nearLimit, isFalse); // 79.9995%, displays 80
      expect(at(159999).sharePercent, 80);
      expect(at(160000).nearLimit, isTrue); // exactly 80%
      expect(at(199999).nearLimit, isTrue); // 99.9995%, displays 100
      expect(at(199999).overLimit, isFalse);
      expect(at(200000).overLimit, isTrue);
      expect(at(280000).overLimit, isTrue);
      expect(at(280000).share, closeTo(1.4, 1e-9));
      expect(at(280000).leftMinor, rupees(-800));
    });

    test(
      'only the given month counts, and unknown categories are left out',
      () {
        final entries = [
          expense(500, oct5),
          expense(900, DateTime(2026, 9, 30, 23, 59, 59)),
          expense(250, oct5, category: 'nowhere'),
          expense(125, oct5, category: null),
        ];
        final p = positions(entries);
        expect(p.map((c) => c.spentMinor), [rupees(500), 0]);
        // They still count toward the month's total.
        final month = monthlyPosition(
          budgetMinor: budget,
          entries: entries,
          now: oct5,
        );
        expect(month.spentMinor, rupees(875));
      },
    );

    test('zero-limit category does not divide by zero', () {
      final none = category('none', 0);
      final untouched = CategoryPosition(category: none, spentMinor: 0);
      expect(untouched.share, 0);
      expect(untouched.sharePercent, 0);
      expect(untouched.nearLimit, isFalse);
      expect(untouched.overLimit, isFalse);

      final used = categoryPositions(
        entries: [expense(10, oct5, category: 'none')],
        categories: [none],
        now: oct5,
      ).single;
      expect(used.share, 1);
      expect(used.sharePercent, 100);
      expect(used.share.isFinite, isTrue);
      expect(used.nearLimit, isFalse);
      expect(used.overLimit, isTrue);
    });
  });

  group('budgetSnapshot', () {
    test('gathers every figure for the month', () {
      final cats = [category('food', 6000), category('shop', 2000)];
      final s = budgetSnapshot(
        budgetMinor: budget,
        entries: [
          expense(14549, oct5, category: 'bills'),
          expense(1850, oct5, category: 'shop'),
          expense(999, DateTime(2026, 9, 5)),
        ],
        categories: cats,
        now: oct5,
      );
      expect(s.now, oct5);
      expect(s.budgetMinor, rupees(30000));
      expect(s.incomeMinor, 0);
      expect(s.spentMinor, rupees(16399));
      expect(s.availableMinor, rupees(30000));
      expect(s.remainingMinor, rupees(13601));
      expect(s.fillPercent, 45);
      expect(s.band, StatusBand.runningLower);
      expect(s.moodLabel, 'Running lower');
      expect(s.daysLeft, 27);
      expect(s.safeToSpendTodayMinor, rupees(503));
      expect(s.isOverspent, isFalse);
      expect(s.categories.map((c) => c.category), cats);
      expect(s.categoryById('shop')!.nearLimit, isTrue);
      expect(s.categoryById('food')!.spentMinor, 0);
      expect(s.categoryById('missing'), isNull);
    });

    test('overspent by ₹2,000', () {
      final s = budgetSnapshot(
        budgetMinor: budget,
        entries: [expense(32000, oct5)],
        categories: const [],
        now: oct5,
      );
      expect(formatRupees(s.remainingMinor), '−₹2,000');
      expect(s.isOverspent, isTrue);
      expect(s.fillLevel, 0);
      expect(s.fillPercent, 0);
      expect(s.band, StatusBand.belowTheLine);
      expect(s.safeToSpendTodayMinor, 0);
    });

    test('has value equality', () {
      BudgetSnapshot build() => budgetSnapshot(
        budgetMinor: budget,
        entries: [
          Entry(
            id: 'a',
            type: EntryType.expense,
            amountMinor: rupees(10),
            categoryId: 'food',
            occurredAt: oct5,
          ),
        ],
        categories: [category('food', 6000)],
        now: oct5,
      );
      expect(build(), build());
      expect(build().hashCode, build().hashCode);
    });
  });
}
