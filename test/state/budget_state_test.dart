import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide/budget/budget.dart';
import 'package:tide/state/budget_state.dart';
import 'package:tide/state/clock.dart';
import 'package:tide/state/ids.dart';
import 'package:tide/state/seed.dart';

ProviderContainer containerAt(DateTime now) => ProviderContainer.test(
  overrides: [clockProvider.overrideWithValue(() => now)],
);

void main() {
  final oct5 = DateTime(2026, 10, 5, 10);

  group('seeded state', () {
    test('on 5 October 2026 shows the prototype figures', () {
      final c = containerAt(oct5);
      final s = c.read(budgetSnapshotProvider);

      expect(s.availableMinor, rupees(30000));
      expect(s.remainingMinor, rupees(13601));
      expect(formatRupees(s.remainingMinor), '₹13,601');
      expect(s.fillLevel.toStringAsFixed(2), '0.45');
      expect(s.fillPercent, 45);
      expect(s.band, StatusBand.runningLower);
      expect(s.moodLabel, 'Running lower');
      expect(s.daysLeft, 27);
      expect(s.safeToSpendTodayMinor, rupees(503));
    });

    test('holds the budget, six categories and twelve entries', () {
      final state = containerAt(oct5).read(budgetProvider);

      expect(state.budgetMinor, rupees(30000));
      expect(state.categories.map((c) => c.id), [
        'food',
        'bills',
        'travel',
        'shop',
        'fun',
        'health',
      ]);
      expect(state.categories.map((c) => c.name), [
        'Food',
        'Bills',
        'Travel',
        'Shopping',
        'Fun',
        'Health',
      ]);
      expect(state.categories.map((c) => c.limitMinor), [
        rupees(6000),
        rupees(11000),
        rupees(3000),
        rupees(2000),
        rupees(1500),
        rupees(1500),
      ]);
      expect(state.categories.first.colorValue, 0xFFF2B880);

      expect(state.entries, hasLength(12));
      expect(state.entries.map((e) => e.id).toSet(), hasLength(12));
      expect(state.entries.every((e) => e.isExpense), isTrue);
      expect(
        state.entries.every((e) => e.source == EntrySource.manual),
        isTrue,
      );
      expect(state.entries.first.note, 'Rent share');
      expect(state.entries.map((e) => e.occurredAt.day), [
        1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, //
      ]);
    });

    test('category spends match the prototype', () {
      final s = containerAt(oct5).read(budgetSnapshotProvider);
      int spent(String id) => s.categoryById(id)!.spentMinor;

      expect(spent('food'), rupees(2330));
      expect(s.categoryById('food')!.sharePercent, 39);
      expect(spent('bills'), rupees(10400));
      expect(s.categoryById('bills')!.nearLimit, isTrue);
      expect(spent('travel'), rupees(670));
      expect(spent('shop'), rupees(1850));
      expect(s.categoryById('shop')!.nearLimit, isTrue);
      expect(spent('fun'), rupees(499));
      expect(spent('health'), rupees(650));
      expect(s.categories.any((c) => c.overLimit), isFalse);
    });

    test('on the 2nd of a month still shows ₹13,601 remaining', () {
      final c = containerAt(DateTime(2027, 2, 2, 8));
      final state = c.read(budgetProvider);

      expect(state.entries.map((e) => e.occurredAt.day), [
        1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, //
      ]);
      expect(
        state.entries.every(
          (e) => e.occurredAt.year == 2027 && e.occurredAt.month == 2,
        ),
        isTrue,
      );
      expect(c.read(budgetSnapshotProvider).remainingMinor, rupees(13601));
    });

    test('shows ₹13,601 remaining on any day of any month', () {
      for (final now in [
        DateTime(2026, 1, 1),
        DateTime(2028, 2, 29, 23, 59, 59),
        DateTime(2026, 12, 31, 23, 59, 59),
      ]) {
        final s = containerAt(now).read(budgetSnapshotProvider);
        expect(s.remainingMinor, rupees(13601), reason: '$now');
      }
    });

    test('offers six income sources', () {
      expect(incomeSources, [
        'Salary',
        'Freelance',
        'Gift',
        'Refund',
        'Cashback',
        'Other',
      ]);
    });
  });

  group('actions', () {
    test('adding an expense then removing it restores the snapshot', () {
      final c = containerAt(oct5);
      final before = c.read(budgetSnapshotProvider);
      final notifier = c.read(budgetProvider.notifier);

      final entry = notifier.addExpense(
        amountMinor: rupees(250),
        categoryId: 'food',
        note: 'Food',
      );
      expect(entry.occurredAt, oct5);
      expect(entry.type, EntryType.expense);
      expect(c.read(budgetProvider).entries.last, entry);

      final during = c.read(budgetSnapshotProvider);
      expect(during.remainingMinor, rupees(13351));
      expect(during.availableMinor, rupees(30000));
      expect(during.categoryById('food')!.spentMinor, rupees(2580));
      expect(during, isNot(before));

      expect(notifier.removeEntry(entry.id), isTrue);
      expect(c.read(budgetSnapshotProvider), before);
      expect(c.read(budgetProvider).entries, hasLength(12));
    });

    test('adding income raises available and remaining', () {
      final c = containerAt(oct5);
      final before = c.read(budgetSnapshotProvider);

      final entry = c
          .read(budgetProvider.notifier)
          .addIncome(amountMinor: rupees(5000), note: 'Freelance');
      expect(entry.type, EntryType.income);
      expect(entry.categoryId, isNull);

      final after = c.read(budgetSnapshotProvider);
      expect(after.availableMinor, rupees(35000));
      expect(after.remainingMinor, rupees(18601));
      expect(after.band, StatusBand.calmWater);
      expect(
        after.categories.map((p) => p.spentMinor),
        before.categories.map((p) => p.spentMinor),
      );
    });

    test('overspending and then adding income recovers', () {
      final c = containerAt(oct5);
      final notifier = c.read(budgetProvider.notifier);

      notifier.addExpense(amountMinor: rupees(15601), categoryId: 'shop');
      final over = c.read(budgetSnapshotProvider);
      expect(formatRupees(over.remainingMinor), '−₹2,000');
      expect(over.moodLabel, 'Below the line');
      expect(over.safeToSpendTodayMinor, 0);
      expect(over.categoryById('shop')!.overLimit, isTrue);

      notifier.addIncome(amountMinor: rupees(5000), note: 'Salary');
      final back = c.read(budgetSnapshotProvider);
      expect(back.remainingMinor, rupees(3000));
      expect(back.moodLabel, 'Nearly dry');
    });

    test('addEntry keeps the entry as given; other months do not count', () {
      final c = containerAt(oct5);
      final before = c.read(budgetSnapshotProvider);
      final old = Entry(
        id: 'old',
        type: EntryType.expense,
        amountMinor: rupees(900),
        categoryId: 'food',
        occurredAt: DateTime(2026, 9, 30, 23, 59, 59),
      );

      c.read(budgetProvider.notifier).addEntry(old);
      expect(c.read(budgetProvider).entries.last, old);
      expect(c.read(budgetSnapshotProvider), before);
    });

    test('removing an unknown id changes nothing', () {
      final c = containerAt(oct5);
      final before = c.read(budgetProvider);

      expect(c.read(budgetProvider.notifier).removeEntry('nope'), isFalse);
      expect(c.read(budgetProvider), same(before));
    });

    test('listeners hear each change', () {
      final c = containerAt(oct5);
      final seen = <int>[];
      c.listen(budgetProvider, (_, next) => seen.add(next.entries.length));
      final sub = c.listen(budgetSnapshotProvider, (_, _) {});
      final notifier = c.read(budgetProvider.notifier);

      final entry = notifier.addExpense(
        amountMinor: rupees(100),
        categoryId: 'fun',
      );
      // The derived snapshot is recomputed the next time it is read.
      expect(sub.read().remainingMinor, rupees(13501));
      notifier.removeEntry(entry.id);
      expect(sub.read().remainingMinor, rupees(13601));
      expect(seen, [13, 12]);
    });

    test('new entry ids are unique', () {
      final ids = {for (var i = 0; i < 1000; i++) newEntryId()};
      expect(ids, hasLength(1000));
    });

    test('state lists cannot be changed from outside', () {
      final state = containerAt(oct5).read(budgetProvider);
      expect(() => state.entries.clear(), throwsUnsupportedError);
      expect(() => state.categories.clear(), throwsUnsupportedError);
    });
  });
}
