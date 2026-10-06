import 'package:flutter_test/flutter_test.dart';
import 'package:tide/budget/budget.dart';
import 'package:tide/log/chips.dart';
import 'package:tide/state/seed.dart';
import 'package:tide/storage/storage.dart';

import '../support/failing_ledger_store.dart';
import 'ledger_store_contract.dart';

void main() {
  ledgerStoreContract('MemoryLedgerStore', () async => MemoryLedgerStore());

  group('MemoryLedgerStore', () {
    test(
      'the sample month holds the seed entries, categories and budget',
      () async {
        final now = DateTime(2026, 10, 5, 14, 30);
        final store = MemoryLedgerStore.sampleMonth(now);
        final month = YearMonth.of(now);

        final entries = await store.entriesForMonth(month);
        expect(entries, seedEntries(now));
        expect(await store.loadCategories(), seedCategories);
        expect(await store.budgetFor(month), seedBudgetMinor);
        expect(await store.hasAnyBudget(), isTrue);
        expect(await store.loadProfile(), isNull);
        expect(
          await store.frequentExpenseAmounts(),
          frequentAmounts(seedEntries(now)),
        );

        // The figures the home screen shows for the sample month.
        final snapshot = budgetSnapshot(
          budgetMinor: (await store.budgetFor(month))!,
          entries: entries,
          categories: await store.loadCategories(),
          now: now,
        );
        expect(snapshot.spentMinor, rupees(16399));
        expect(snapshot.remainingMinor, rupees(13601));
      },
    );

    test(
      'the sample month follows the date given, early in a month too',
      () async {
        final now = DateTime(2027, 1, 2, 8);
        final store = MemoryLedgerStore.sampleMonth(
          now,
          profile: Profile(monthlyIncomeMinor: rupees(45000)),
        );
        final entries = await store.entriesForMonth(const YearMonth(2027, 1));
        expect(entries.length, 12);
        expect(entries.every((e) => e.occurredAt.day <= 2), isTrue);
        expect(await store.entriesForMonth(const YearMonth(2026, 12)), isEmpty);
        expect(await store.budgetFor(const YearMonth(2026, 12)), isNull);
        expect((await store.loadProfile())!.monthlyIncomeMinor, rupees(45000));
      },
    );

    test('starting data is copied, not shared', () async {
      final categories = [...seedCategories];
      final budgets = {const YearMonth(2026, 10): rupees(30000)};
      final store = MemoryLedgerStore(categories: categories, budgets: budgets);
      await store.saveCategoryLimit('food', rupees(1));
      await store.setBudget(const YearMonth(2026, 10), rupees(1));
      expect(categories, seedCategories);
      expect(budgets.values.single, rupees(30000));
      (await store.loadCategories()).clear();
      expect((await store.loadCategories()).length, 6);
    });

    test('a closed store refuses further use', () async {
      final store = MemoryLedgerStore();
      await store.close();
      expect(store.isClosed, isTrue);
      await expectLater(store.loadCategories(), throwsStateError);
    });
  });

  group('FailingLedgerStore', () {
    final entry = Entry(
      id: 'f-1',
      type: EntryType.expense,
      amountMinor: rupees(250),
      categoryId: 'food',
      occurredAt: DateTime(2026, 10, 5, 12),
    );
    const oct = YearMonth(2026, 10);

    test('passes everything through until told to fail', () async {
      final store = FailingLedgerStore(
        inner: MemoryLedgerStore.sampleMonth(DateTime(2026, 10, 5)),
      );
      await store.insertEntry(entry);
      expect((await store.entriesForMonth(oct)).length, 13);
      expect(await store.softDeleteEntry('f-1'), isTrue);
      expect(await store.saveCategoryLimit('food', rupees(8000)), isTrue);
      expect(store.failures, 0);
    });

    test('throws on insert and records nothing', () async {
      final store = FailingLedgerStore(failOnInsert: true);
      await expectLater(
        store.insertEntry(entry),
        throwsA(isA<LedgerStoreFailure>()),
      );
      expect(await store.entriesForMonth(oct), isEmpty);
      expect(store.failures, 1);

      store.failOnInsert = false;
      await store.insertEntry(entry);
      expect(await store.entriesForMonth(oct), [entry]);
    });

    test('throws on delete and leaves the entry', () async {
      final store = FailingLedgerStore();
      await store.insertEntry(entry);
      store.failOnDelete = true;
      await expectLater(
        store.softDeleteEntry(entry.id),
        throwsA(isA<LedgerStoreFailure>()),
      );
      expect(await store.entriesForMonth(oct), [entry]);
      // Inserting still works while only delete fails.
      await store.insertEntry(
        Entry(
          id: 'f-2',
          type: EntryType.expense,
          amountMinor: rupees(10),
          occurredAt: DateTime(2026, 10, 6),
        ),
      );
    });

    test('throws on every kind of save and changes nothing', () async {
      final store = FailingLedgerStore(
        inner: MemoryLedgerStore.sampleMonth(DateTime(2026, 10, 5)),
        failOnSave: true,
      );
      final failure = throwsA(isA<LedgerStoreFailure>());
      await expectLater(store.setBudget(oct, rupees(1)), failure);
      await expectLater(store.saveCategoryLimit('food', rupees(1)), failure);
      await expectLater(store.replaceCategories(const []), failure);
      await expectLater(
        store.saveProfile(const Profile(monthlyIncomeMinor: 100)),
        failure,
      );
      expect(store.failures, 4);
      expect(await store.budgetFor(oct), seedBudgetMinor);
      expect(await store.loadCategories(), seedCategories);
      expect(await store.loadProfile(), isNull);
      // Entries are unaffected by the save switch.
      await store.insertEntry(entry);
    });
  });
}
