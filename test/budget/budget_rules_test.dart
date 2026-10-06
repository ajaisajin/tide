import 'package:flutter_test/flutter_test.dart';
import 'package:tide/budget/budget.dart';

void main() {
  group('Default category limits', () {
    test('budget of ₹30,000', () {
      expect(defaultCategoryLimits(rupees(30000)), {
        'food': rupees(6000),
        'bills': rupees(10500),
        'travel': rupees(3000),
        'shop': rupees(2100),
        'fun': rupees(1500),
        'health': rupees(1500),
      });
    });

    test('rounding down: budget of ₹18,400', () {
      final limits = defaultCategoryLimits(rupees(18400));
      expect(limits['food'], rupees(3600)); // 20% is ₹3,680
      expect(limits['shop'], rupees(1200)); // 7% is ₹1,288
      expect(limits['bills'], rupees(6400)); // 35% is ₹6,440
    });

    test('very small budget: no limit is below ₹100', () {
      final limits = defaultCategoryLimits(rupees(1000));
      expect(limits.values.every((l) => l >= rupees(100)), isTrue);
      expect(limits, {
        'food': rupees(200),
        'bills': rupees(300),
        'travel': rupees(100),
        'shop': rupees(100), // 7% is ₹70, raised to the floor
        'fun': rupees(100),
        'health': rupees(100),
      });
    });

    test('every limit is a multiple of ₹100 and at least ₹100, for a spread '
        'of budgets', () {
      for (final budget in [0, 1, 99, 100, 1437, 9999, 45250, 9999999]) {
        final limits = defaultCategoryLimits(rupees(budget));
        expect(limits.keys, [
          'food',
          'bills',
          'travel',
          'shop',
          'fun',
          'health',
        ]);
        for (final limit in limits.values) {
          expect(limit % rupees(100), 0, reason: 'budget ₹$budget');
          expect(limit, greaterThanOrEqualTo(rupees(100)));
        }
      }
    });

    test('a negative budget is treated as nothing', () {
      expect(defaultCategoryLimits(-500).values.toSet(), {rupees(100)});
    });
  });

  group('One budget per month, carried forward', () {
    const sep = YearMonth(2026, 9);
    const oct = YearMonth(2026, 10);
    const nov = YearMonth(2026, 11);

    test('new month with nothing set uses the previous budget', () {
      expect(effectiveBudgetMinor({oct: rupees(30000)}, nov), rupees(30000));
    });

    test('changing the new month only leaves the earlier one alone', () {
      final budgets = {oct: rupees(30000), nov: rupees(32000)};
      expect(effectiveBudgetMinor(budgets, nov), rupees(32000));
      expect(effectiveBudgetMinor(budgets, oct), rupees(30000));
    });

    test('a month earlier than any budget has none', () {
      expect(effectiveBudgetMinor({oct: rupees(30000)}, sep), isNull);
      expect(effectiveBudgetMinor({}, oct), isNull);
    });

    test('carries across a year boundary and over gaps', () {
      final budgets = {
        const YearMonth(2026, 3): rupees(20000),
        const YearMonth(2026, 12): rupees(30000),
        const YearMonth(2027, 6): rupees(40000),
      };
      expect(
        effectiveBudgetMinor(budgets, const YearMonth(2027, 1)),
        rupees(30000),
      );
      expect(
        effectiveBudgetMinor(budgets, const YearMonth(2026, 11)),
        rupees(20000),
      );
      expect(
        effectiveBudgetMinor(budgets, const YearMonth(2030, 1)),
        rupees(40000),
      );
      // December 2025 is before March 2026 even though 12 > 3.
      expect(effectiveBudgetMinor(budgets, const YearMonth(2025, 12)), isNull);
    });
  });

  group('Setting the budget by filling the vessel', () {
    test('dragging up: two thirds of ₹45,000 is ₹30,000, ₹15,000 set '
        'aside', () {
      final income = rupees(45000);
      final budget = budgetForLevel(level: 2 / 3, incomeMinor: income);
      expect(budget, rupees(30000));
      expect(income - budget, rupees(15000));
    });

    test('top of the vessel: past the top stays at the income', () {
      final income = rupees(45000);
      expect(budgetForLevel(level: 1, incomeMinor: income), income);
      expect(budgetForLevel(level: 1.4, incomeMinor: income), income);
      expect(
        budgetForLevel(level: double.infinity, incomeMinor: income),
        income,
      );
    });

    test('bottom of the vessel: below the bottom is ₹0', () {
      final income = rupees(45000);
      expect(budgetForLevel(level: 0, incomeMinor: income), 0);
      expect(budgetForLevel(level: -0.2, incomeMinor: income), 0);
      expect(budgetForLevel(level: double.nan, incomeMinor: income), 0);
    });

    test('small income: ₹6,000 moves in steps of ₹100', () {
      final income = rupees(6000);
      expect(budgetStepMinor(income), rupees(100));
      final seen = <int>{
        for (var i = 0; i <= 1000; i++)
          budgetForLevel(level: i / 1000, incomeMinor: income),
      }.toList()..sort();
      expect(seen.length, 61);
      for (var i = 0; i < seen.length; i++) {
        expect(seen[i], rupees(100) * i);
      }
    });

    test('₹500 steps from ₹10,000 of income, ₹100 below', () {
      expect(budgetStepMinor(rupees(9999)), rupees(100));
      expect(budgetStepMinor(rupees(10000)), rupees(500));
      expect(budgetStepMinor(rupees(45000)), rupees(500));
      for (var i = 0; i <= 1000; i++) {
        final b = budgetForLevel(level: i / 1000, incomeMinor: rupees(45000));
        expect(b % rupees(500), 0);
        expect(b, inInclusiveRange(0, rupees(45000)));
      }
    });

    test('an income that is not a whole number of steps still tops out at '
        'the income', () {
      final income = rupees(45250);
      expect(budgetForLevel(level: 1, incomeMinor: income), income);
      // Just below the top is the last whole step, not the income.
      expect(budgetForLevel(level: 0.9999, incomeMinor: income), rupees(45000));
      expect(budgetForLevel(level: 0.99, incomeMinor: income), rupees(45000));
    });

    test('no income gives no budget', () {
      expect(budgetForLevel(level: 0.5, incomeMinor: 0), 0);
      expect(levelForBudget(budgetMinor: rupees(100), incomeMinor: 0), 0);
    });

    test('level for a budget is its share of income, kept within 0 to 1', () {
      final income = rupees(45000);
      expect(
        levelForBudget(budgetMinor: rupees(30000), incomeMinor: income),
        closeTo(2 / 3, 1e-12),
      );
      expect(
        levelForBudget(budgetMinor: rupees(28750), incomeMinor: income),
        closeTo(28750 / 45000, 1e-12),
      );
      expect(levelForBudget(budgetMinor: 0, incomeMinor: income), 0);
      expect(levelForBudget(budgetMinor: income, incomeMinor: income), 1);
      expect(levelForBudget(budgetMinor: income * 2, incomeMinor: income), 1);
      expect(levelForBudget(budgetMinor: -5, incomeMinor: income), 0);
    });

    test('level and budget round-trip on every step', () {
      for (final income in [rupees(6000), rupees(45000), rupees(45250)]) {
        final step = budgetStepMinor(income);
        for (var b = 0; b <= income; b += step) {
          final level = levelForBudget(budgetMinor: b, incomeMinor: income);
          expect(budgetForLevel(level: level, incomeMinor: income), b);
        }
      }
    });

    test('one step up and one step down', () {
      final income = rupees(45000);
      expect(
        stepBudgetUp(budgetMinor: rupees(30000), incomeMinor: income),
        rupees(30500),
      );
      expect(
        stepBudgetDown(budgetMinor: rupees(30000), incomeMinor: income),
        rupees(29500),
      );
      // Ends.
      expect(stepBudgetUp(budgetMinor: income, incomeMinor: income), income);
      expect(stepBudgetDown(budgetMinor: 0, incomeMinor: income), 0);
      expect(stepBudgetUp(budgetMinor: 0, incomeMinor: income), rupees(500));
      expect(
        stepBudgetDown(budgetMinor: income, incomeMinor: income),
        rupees(44500),
      );
      // A typed amount between steps moves onto the neighbouring step.
      expect(
        stepBudgetUp(budgetMinor: rupees(28750), incomeMinor: income),
        rupees(29000),
      );
      expect(
        stepBudgetDown(budgetMinor: rupees(28750), incomeMinor: income),
        rupees(28500),
      );
      // Small income steps by ₹100.
      expect(
        stepBudgetUp(budgetMinor: rupees(3000), incomeMinor: rupees(6000)),
        rupees(3100),
      );
      expect(
        stepBudgetDown(budgetMinor: rupees(3000), incomeMinor: rupees(6000)),
        rupees(2900),
      );
      // Income off the step grid.
      expect(
        stepBudgetUp(budgetMinor: rupees(45000), incomeMinor: rupees(45250)),
        rupees(45250),
      );
      expect(
        stepBudgetDown(budgetMinor: rupees(45250), incomeMinor: rupees(45250)),
        rupees(45000),
      );
      expect(stepBudgetUp(budgetMinor: rupees(100), incomeMinor: 0), 0);
    });
  });

  group('Typing the budget', () {
    final income = rupees(45000);

    test('exact amount: ₹28,750 is accepted', () {
      expect(
        checkTypedBudget(budgetMinor: rupees(28750), incomeMinor: income),
        BudgetCheck.ok,
      );
    });

    test('more than income: ₹50,000 is refused', () {
      expect(
        checkTypedBudget(budgetMinor: rupees(50000), incomeMinor: income),
        BudgetCheck.aboveIncome,
      );
    });

    test('bounds are ₹1 and the income itself', () {
      BudgetCheck check(int minor) =>
          checkTypedBudget(budgetMinor: minor, incomeMinor: income);
      expect(check(0), BudgetCheck.belowMinimum);
      expect(check(rupees(1) - 1), BudgetCheck.belowMinimum);
      expect(check(rupees(1)), BudgetCheck.ok);
      expect(check(income), BudgetCheck.ok);
      expect(check(income + rupees(1)), BudgetCheck.aboveIncome);
      expect(check(rupees(100) + 50), BudgetCheck.notWholeRupees);
      expect(BudgetCheck.ok.isOk, isTrue);
      expect(BudgetCheck.aboveIncome.isOk, isFalse);
    });
  });

  group('Income and limit amounts', () {
    test('₹1 to ₹99,99,999', () {
      for (final check in [checkIncome, checkCategoryLimit]) {
        expect(check(0), AmountCheck.belowMinimum);
        expect(check(-rupees(5)), AmountCheck.belowMinimum);
        expect(check(rupees(1) - 1), AmountCheck.belowMinimum);
        expect(check(rupees(1)), AmountCheck.ok);
        expect(check(rupees(45000)), AmountCheck.ok);
        expect(check(rupees(9999999)), AmountCheck.ok);
        expect(check(rupees(9999999) + 1), AmountCheck.aboveMaximum);
        expect(check(rupees(10000000)), AmountCheck.aboveMaximum);
        expect(check(rupees(250) + 50), AmountCheck.notWholeRupees);
      }
      expect(minAmountMinor, rupees(1));
      expect(maxAmountMinor, rupees(9999999));
      expect(formatRupees(maxAmountMinor), '₹99,99,999');
      expect(AmountCheck.ok.isOk, isTrue);
      expect(AmountCheck.aboveMaximum.isOk, isFalse);
    });
  });

  group('Limits against the budget', () {
    test('limits of ₹34,000 are ₹4,000 more than a ₹30,000 budget', () {
      final c = compareLimitsWithBudget(
        limitsMinor: [
          rupees(8000),
          rupees(12500),
          rupees(5000),
          rupees(4100),
          rupees(2200),
          rupees(2200),
        ],
        budgetMinor: rupees(30000),
      );
      expect(c.totalMinor, rupees(34000));
      expect(c.isOverBudget, isTrue);
      expect(c.overByMinor, rupees(4000));
      expect(c.unallocatedMinor, 0);
    });

    test('the default limits for ₹30,000 total ₹24,600 and are not over', () {
      final c = compareLimitsWithBudget(
        limitsMinor: defaultCategoryLimits(rupees(30000)).values,
        budgetMinor: rupees(30000),
      );
      expect(c.totalMinor, rupees(24600));
      expect(c.isOverBudget, isFalse);
      expect(c.overByMinor, 0);
      expect(c.unallocatedMinor, rupees(5400));
    });

    test('limits equal to the budget are not over', () {
      final c = compareLimitsWithBudget(
        limitsMinor: [rupees(10000), rupees(20000)],
        budgetMinor: rupees(30000),
      );
      expect(c.isOverBudget, isFalse);
      expect(c.overByMinor, 0);
      expect(
        c,
        LimitsComparison(totalMinor: rupees(30000), budgetMinor: rupees(30000)),
      );
    });

    test('no limits total nothing', () {
      final c = compareLimitsWithBudget(limitsMinor: [], budgetMinor: 0);
      expect(c.totalMinor, 0);
      expect(c.isOverBudget, isFalse);
    });
  });
}
