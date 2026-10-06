import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide/budget/budget.dart';
import 'package:tide/state/budget_state.dart';
import 'package:tide/state/ledger.dart';
import 'package:tide/state/seed.dart';
import 'package:tide/storage/storage.dart';

import '../support/failing_ledger_store.dart';
import '../support/gated_ledger_store.dart';
import '../support/ledger_container.dart';

/// A container on the sample month for [now], loaded from an in-memory store.
Future<ProviderContainer> containerAt(DateTime now) =>
    ledgerContainer(now: now);

/// Lets futures that are already due run.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  final oct5 = DateTime(2026, 10, 5, 10);

  group('state loaded from a store holding the sample month', () {
    test('on 5 October 2026 shows the prototype figures', () async {
      final c = await containerAt(oct5);
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

    test('holds the budget, six categories and twelve entries', () async {
      final state = (await containerAt(oct5)).read(budgetProvider);

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

    test('category spends match the prototype', () async {
      final s = (await containerAt(oct5)).read(budgetSnapshotProvider);
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

    test('on the 2nd of a month still shows ₹13,601 remaining', () async {
      final c = await containerAt(DateTime(2027, 2, 2, 8));
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

    test('shows ₹13,601 remaining on any day of any month', () async {
      for (final now in [
        DateTime(2026, 1, 1),
        DateTime(2028, 2, 29, 23, 59, 59),
        DateTime(2026, 12, 31, 23, 59, 59),
      ]) {
        final s = (await containerAt(now)).read(budgetSnapshotProvider);
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

  group('state loaded from a store', () {
    test('holds what the store holds, not the sample month', () async {
      final store = MemoryLedgerStore(
        entries: [
          Entry(
            id: 'a',
            type: EntryType.expense,
            amountMinor: rupees(1200),
            categoryId: 'food',
            occurredAt: DateTime(2026, 10, 3, 9),
          ),
          Entry(
            id: 'september',
            type: EntryType.expense,
            amountMinor: rupees(999),
            categoryId: 'food',
            occurredAt: DateTime(2026, 9, 30, 23, 59),
          ),
        ],
        categories: [seedCategories.first],
        budgets: {const YearMonth(2026, 9): rupees(42000)},
        profile: Profile(monthlyIncomeMinor: rupees(60000)),
      );
      final c = await ledgerContainer(now: oct5, store: store);
      final state = c.read(budgetProvider);

      expect(state.month, const YearMonth(2026, 10));
      expect(state.entries.map((e) => e.id), ['a']);
      expect(state.categories, [seedCategories.first]);
      // September's budget, carried forward.
      expect(state.budgetMinor, rupees(42000));
      expect(state.incomeMinor, rupees(60000));
      expect(state.setupComplete, isTrue);
      expect(c.read(budgetSnapshotProvider).remainingMinor, rupees(40800));
    });

    test('an empty store is one where setup is not complete', () async {
      final c = await ledgerContainer(now: oct5, store: MemoryLedgerStore());
      final state = c.read(budgetProvider);

      expect(state.setupComplete, isFalse);
      expect(state.budgetMinor, 0);
      expect(state.incomeMinor, isNull);
      expect(state.entries, isEmpty);
      expect(state.categories, isEmpty);
    });
  });

  group('actions', () {
    test('adding an expense then removing it restores the snapshot', () async {
      final c = await containerAt(oct5);
      final before = c.read(budgetSnapshotProvider);
      final notifier = c.read(budgetProvider.notifier);

      final entry = await notifier.addExpense(
        amountMinor: rupees(250),
        categoryId: 'food',
        note: 'Food',
      );
      expect(entry.occurredAt, oct5);
      expect(entry.type, EntryType.expense);
      expect(isUuidV7(entry.id), isTrue);
      expect(c.read(budgetProvider).entries.last, entry);

      final during = c.read(budgetSnapshotProvider);
      expect(during.remainingMinor, rupees(13351));
      expect(during.availableMinor, rupees(30000));
      expect(during.categoryById('food')!.spentMinor, rupees(2580));
      expect(during, isNot(before));

      expect(await notifier.removeEntry(entry.id), isTrue);
      expect(c.read(budgetSnapshotProvider), before);
      expect(c.read(budgetProvider).entries, hasLength(12));
    });

    test('adding income raises available and remaining', () async {
      final c = await containerAt(oct5);
      final before = c.read(budgetSnapshotProvider);

      final entry = await c
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

    test('overspending and then adding income recovers', () async {
      final c = await containerAt(oct5);
      final notifier = c.read(budgetProvider.notifier);

      await notifier.addExpense(amountMinor: rupees(15601), categoryId: 'shop');
      final over = c.read(budgetSnapshotProvider);
      expect(formatRupees(over.remainingMinor), '−₹2,000');
      expect(over.moodLabel, 'Below the line');
      expect(over.safeToSpendTodayMinor, 0);
      expect(over.categoryById('shop')!.overLimit, isTrue);

      await notifier.addIncome(amountMinor: rupees(5000), note: 'Salary');
      final back = c.read(budgetSnapshotProvider);
      expect(back.remainingMinor, rupees(3000));
      expect(back.moodLabel, 'Nearly dry');
    });

    test('an entry dated in another month is saved but not held', () async {
      final store = MemoryLedgerStore.sampleMonth(oct5);
      final c = await ledgerContainer(now: oct5, store: store);
      final before = c.read(budgetProvider);
      final old = Entry(
        id: 'old',
        type: EntryType.expense,
        amountMinor: rupees(900),
        categoryId: 'food',
        occurredAt: DateTime(2026, 9, 30, 23, 59, 59),
      );

      expect(await c.read(budgetProvider.notifier).addEntry(old), old);
      expect(c.read(budgetProvider), same(before));
      expect(await store.entriesForMonth(const YearMonth(2026, 9)), [old]);
    });

    test('removing an unknown id changes nothing', () async {
      final c = await containerAt(oct5);
      final before = c.read(budgetProvider);

      expect(
        await c.read(budgetProvider.notifier).removeEntry('nope'),
        isFalse,
      );
      expect(c.read(budgetProvider), same(before));
    });

    test('listeners hear each change', () async {
      final c = await containerAt(oct5);
      final seen = <int>[];
      c.listen(budgetProvider, (_, next) => seen.add(next.entries.length));
      final sub = c.listen(budgetSnapshotProvider, (_, _) {});
      final notifier = c.read(budgetProvider.notifier);

      final entry = await notifier.addExpense(
        amountMinor: rupees(100),
        categoryId: 'fun',
      );
      // The derived snapshot is recomputed the next time it is read.
      expect(sub.read().remainingMinor, rupees(13501));
      await notifier.removeEntry(entry.id);
      expect(sub.read().remainingMinor, rupees(13601));
      expect(seen, [13, 12]);
    });

    test('state lists cannot be changed from outside', () async {
      final state = (await containerAt(oct5)).read(budgetProvider);
      expect(() => state.entries.clear(), throwsUnsupportedError);
      expect(() => state.categories.clear(), throwsUnsupportedError);
    });
  });

  group('writes reach the store before the state', () {
    Future<(ProviderContainer, GatedLedgerStore)> gated() async {
      final store = GatedLedgerStore(
        inner: MemoryLedgerStore.sampleMonth(oct5),
      );
      return (await ledgerContainer(now: oct5, store: store), store);
    }

    test('an expense joins the state only once it is saved', () async {
      final (c, store) = await gated();
      final before = c.read(budgetProvider);

      store.hold();
      final adding = c
          .read(budgetProvider.notifier)
          .addExpense(amountMinor: rupees(250), categoryId: 'food');
      await settle();
      expect(store.inserts, 1);
      expect(c.read(budgetProvider), same(before));
      expect(await store.entriesForMonth(before.month), hasLength(12));

      store.release();
      final entry = await adding;
      expect(c.read(budgetProvider).entries.last, entry);
      expect(await store.entriesForMonth(before.month), contains(entry));
      expect(c.read(budgetSnapshotProvider).remainingMinor, rupees(13351));
    });

    test('income joins the state only once it is saved', () async {
      final (c, store) = await gated();
      final before = c.read(budgetProvider);

      store.hold();
      final adding = c
          .read(budgetProvider.notifier)
          .addIncome(amountMinor: rupees(5000), note: 'Gift');
      await settle();
      expect(c.read(budgetProvider), same(before));

      store.release();
      await adding;
      expect(c.read(budgetSnapshotProvider).availableMinor, rupees(35000));
    });

    test('an entry leaves the state only once it is deleted', () async {
      final (c, store) = await gated();
      final before = c.read(budgetProvider);

      store.hold();
      final removing = c.read(budgetProvider.notifier).removeEntry('seed-1');
      await settle();
      expect(store.deletes, 1);
      expect(c.read(budgetProvider), same(before));

      store.release();
      expect(await removing, isTrue);
      expect(c.read(budgetProvider).entries.map((e) => e.id), [
        for (var i = 2; i <= 12; i++) 'seed-$i',
      ]);
      expect(
        (await store.entriesForMonth(before.month)).map((e) => e.id),
        isNot(contains('seed-1')),
      );
    });

    test('a failed insert throws and leaves the state untouched', () async {
      final (c, store) = await gated();
      final before = c.read(budgetProvider);
      final chips = c.read(frequentAmountsProvider);
      final notifier = c.read(budgetProvider.notifier);
      store.failOnInsert = true;

      await expectLater(
        notifier.addExpense(amountMinor: rupees(250), categoryId: 'food'),
        throwsA(isA<LedgerStoreFailure>()),
      );
      await expectLater(
        notifier.addIncome(amountMinor: rupees(5000)),
        throwsA(isA<LedgerStoreFailure>()),
      );
      await settle();
      expect(c.read(budgetProvider), same(before));
      expect(c.read(frequentAmountsProvider), chips);
      expect(await store.entriesForMonth(before.month), hasLength(12));
    });

    test('a failed delete throws and leaves the state untouched', () async {
      final (c, store) = await gated();
      final before = c.read(budgetProvider);
      store.failOnDelete = true;

      await expectLater(
        c.read(budgetProvider.notifier).removeEntry('seed-1'),
        throwsA(isA<LedgerStoreFailure>()),
      );
      expect(c.read(budgetProvider), same(before));
      expect(await store.entriesForMonth(before.month), hasLength(12));
    });
  });

  group('frequent amounts', () {
    test('start as the store has them', () async {
      final c = await containerAt(oct5);
      expect(c.read(frequentAmountsProvider), [
        for (final r in [650, 180, 450, 920, 280]) rupees(r),
      ]);
    });

    test('count every month, not only the one on show', () async {
      final store = MemoryLedgerStore.sampleMonth(oct5);
      for (var i = 0; i < 2; i++) {
        await store.insertEntry(
          Entry(
            id: 'sep-$i',
            type: EntryType.expense,
            amountMinor: rupees(75),
            categoryId: 'food',
            occurredAt: DateTime(2026, 9, 10 + i),
          ),
        );
      }
      final c = await ledgerContainer(now: oct5, store: store);
      expect(c.read(budgetProvider).entries, hasLength(12));
      expect(c.read(frequentAmountsProvider).first, rupees(75));
    });

    test('are asked for again after each write', () async {
      final c = await containerAt(oct5);
      final notifier = c.read(budgetProvider.notifier);
      expect(c.read(frequentAmountsProvider), isNot(contains(rupees(20))));

      final first = await notifier.addExpense(
        amountMinor: rupees(20),
        categoryId: 'food',
      );
      await notifier.addExpense(amountMinor: rupees(20), categoryId: 'food');
      await settle();
      expect(c.read(frequentAmountsProvider).first, rupees(20));

      await notifier.removeEntry(first.id);
      await settle();
      // Once each, like every other amount, and the most recent of them.
      expect(c.read(frequentAmountsProvider).first, rupees(20));
      expect(c.read(frequentAmountsProvider), hasLength(5));
    });
  });

  group('income, budget and limits', () {
    test('completing setup saves income, default limits and the budget, '
        'and marks setup complete', () async {
      final store = MemoryLedgerStore();
      final c = await ledgerContainer(now: oct5, store: store);

      await c
          .read(budgetProvider.notifier)
          .completeSetup(
            incomeMinor: rupees(45000),
            budgetMinor: rupees(30000),
          );

      final state = c.read(budgetProvider);
      expect(state.setupComplete, isTrue);
      expect(state.budgetMinor, rupees(30000));
      expect(state.incomeMinor, rupees(45000));
      expect(state.categories.map((c) => c.name), [
        'Food',
        'Bills',
        'Travel',
        'Shopping',
        'Fun',
        'Health',
      ]);
      expect(state.categories.map((c) => c.limitMinor), [
        for (final r in [6000, 10500, 3000, 2100, 1500, 1500]) rupees(r),
      ]);
      // Income is a reference figure: it adds nothing to what is available.
      expect(c.read(budgetSnapshotProvider).availableMinor, rupees(30000));

      expect(await store.hasAnyBudget(), isTrue);
      expect(await store.budgetFor(const YearMonth(2026, 10)), rupees(30000));
      expect(
        await store.loadProfile(),
        Profile(monthlyIncomeMinor: rupees(45000)),
      );
      expect(await store.loadCategories(), state.categories);
    });

    test('setup that cannot be saved leaves setup incomplete', () async {
      final store = FailingLedgerStore(failOnSave: true);
      final c = await ledgerContainer(now: oct5, store: store);
      final before = c.read(budgetProvider);

      await expectLater(
        c
            .read(budgetProvider.notifier)
            .completeSetup(
              incomeMinor: rupees(45000),
              budgetMinor: rupees(30000),
            ),
        throwsA(isA<LedgerStoreFailure>()),
      );
      expect(c.read(budgetProvider), same(before));
      expect(await store.hasAnyBudget(), isFalse);
    });

    test('setBudget changes this month only and no limit', () async {
      final store = MemoryLedgerStore.sampleMonth(DateTime(2026, 10, 5));
      final c = await ledgerContainer(now: DateTime(2026, 11, 3), store: store);
      expect(c.read(budgetProvider).budgetMinor, rupees(30000));

      await c.read(budgetProvider.notifier).setBudget(rupees(32000));

      expect(c.read(budgetProvider).budgetMinor, rupees(32000));
      expect(c.read(budgetProvider).categories, seedCategories);
      expect(await store.budgetFor(const YearMonth(2026, 11)), rupees(32000));
      expect(await store.budgetFor(const YearMonth(2026, 10)), rupees(30000));
    });

    test(
      'setIncome and setCategoryLimit save, then change the state',
      () async {
        final store = MemoryLedgerStore.sampleMonth(oct5);
        final c = await ledgerContainer(now: oct5, store: store);
        final notifier = c.read(budgetProvider.notifier);

        await notifier.setIncome(rupees(50000));
        expect(await notifier.setCategoryLimit('food', rupees(8000)), isTrue);
        expect(await notifier.setCategoryLimit('nope', rupees(8000)), isFalse);

        final state = c.read(budgetProvider);
        expect(state.incomeMinor, rupees(50000));
        expect(state.categories.first.limitMinor, rupees(8000));
        expect(state.categories.skip(1), seedCategories.skip(1));
        expect((await store.loadProfile())!.monthlyIncomeMinor, rupees(50000));
        expect((await store.loadCategories()).first.limitMinor, rupees(8000));
      },
    );

    test(
      'a failed save of income, budget or a limit changes nothing',
      () async {
        final store = FailingLedgerStore(
          inner: MemoryLedgerStore.sampleMonth(oct5),
          failOnSave: true,
        );
        final c = await ledgerContainer(now: oct5, store: store);
        final before = c.read(budgetProvider);
        final notifier = c.read(budgetProvider.notifier);

        for (final save in [
          () => notifier.setIncome(rupees(50000)),
          () => notifier.setBudget(rupees(32000)),
          () => notifier.setCategoryLimit('food', rupees(8000)),
        ]) {
          await expectLater(save(), throwsA(isA<LedgerStoreFailure>()));
        }
        expect(c.read(budgetProvider), same(before));
      },
    );

    test('saveBudgetSettings saves income, budget and limits together, then '
        'changes the state', () async {
      final store = MemoryLedgerStore.sampleMonth(DateTime(2026, 10, 5));
      final c = await ledgerContainer(now: DateTime(2026, 11, 3), store: store);

      await c
          .read(budgetProvider.notifier)
          .saveBudgetSettings(
            incomeMinor: rupees(50000),
            budgetMinor: rupees(32000),
            categoryLimitsMinor: {'food': rupees(8000)},
          );

      final state = c.read(budgetProvider);
      expect(state.incomeMinor, rupees(50000));
      expect(state.budgetMinor, rupees(32000));
      expect(state.categories.first.limitMinor, rupees(8000));
      expect(state.categories.skip(1), seedCategories.skip(1));
      expect((await store.loadProfile())!.monthlyIncomeMinor, rupees(50000));
      expect(await store.loadCategories(), state.categories);
      expect(await store.budgetFor(const YearMonth(2026, 11)), rupees(32000));
      // The earlier month keeps its own budget.
      expect(await store.budgetFor(const YearMonth(2026, 10)), rupees(30000));
    });

    test('saveBudgetSettings with only a budget touches no limit and no '
        'income', () async {
      final store = MemoryLedgerStore.sampleMonth(
        oct5,
        profile: Profile(monthlyIncomeMinor: rupees(45000)),
      );
      final c = await ledgerContainer(now: oct5, store: store);

      await c
          .read(budgetProvider.notifier)
          .saveBudgetSettings(budgetMinor: rupees(32000));

      final state = c.read(budgetProvider);
      expect(state.budgetMinor, rupees(32000));
      expect(state.incomeMinor, rupees(45000));
      expect(state.categories, seedCategories);
      expect(await store.loadCategories(), seedCategories);
      expect((await store.loadProfile())!.monthlyIncomeMinor, rupees(45000));
    });

    test('saveBudgetSettings that fails part-way saves nothing and leaves '
        'the state untouched', () async {
      final store = MemoryLedgerStore.sampleMonth(oct5);
      final c = await ledgerContainer(now: oct5, store: store);
      final before = c.read(budgetProvider);

      await expectLater(
        c
            .read(budgetProvider.notifier)
            .saveBudgetSettings(
              incomeMinor: rupees(50000),
              budgetMinor: rupees(32000),
              categoryLimitsMinor: {'food': rupees(8000), 'nope': rupees(1)},
            ),
        throwsA(anything),
      );

      expect(c.read(budgetProvider), same(before));
      expect(await store.loadProfile(), isNull);
      expect(await store.loadCategories(), seedCategories);
      expect(await store.budgetFor(before.month), rupees(30000));
    });

    test(
      'saveBudgetSettings that cannot be saved leaves the state untouched',
      () async {
        final store = FailingLedgerStore(
          inner: MemoryLedgerStore.sampleMonth(oct5),
          failOnSave: true,
        );
        final c = await ledgerContainer(now: oct5, store: store);
        final before = c.read(budgetProvider);

        await expectLater(
          c
              .read(budgetProvider.notifier)
              .saveBudgetSettings(budgetMinor: rupees(32000)),
          throwsA(isA<LedgerStoreFailure>()),
        );
        expect(c.read(budgetProvider), same(before));
        expect(await store.budgetFor(before.month), rupees(30000));
      },
    );
  });
}
