// The behaviour every LedgerStore must have. Run against the in-memory store
// and the Drift store on the host, and against the encrypted store on a
// device (integration_test/), so the three cannot drift apart.
import 'package:flutter_test/flutter_test.dart';
import 'package:tide/budget/budget.dart';
import 'package:tide/log/chips.dart';
import 'package:tide/storage/storage.dart';

const _sep = YearMonth(2026, 9);
const _oct = YearMonth(2026, 10);
const _nov = YearMonth(2026, 11);
const _dec = YearMonth(2026, 12);

var _n = 0;

Entry _expense(
  int rupeeAmount,
  DateTime at, {
  String? id,
  String? categoryId = 'food',
  String note = '',
}) => Entry(
  id: id ?? 'c-${++_n}',
  type: EntryType.expense,
  amountMinor: rupees(rupeeAmount),
  categoryId: categoryId,
  note: note,
  occurredAt: at,
);

Entry _income(int rupeeAmount, DateTime at, {String note = 'Salary'}) => Entry(
  id: 'c-${++_n}',
  type: EntryType.income,
  amountMinor: rupees(rupeeAmount),
  note: note,
  occurredAt: at,
);

final _categories = [
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
    limitMinor: rupees(10500),
  ),
  Category(
    id: 'travel',
    name: 'Travel',
    colorValue: 0xFF8FB8F2,
    limitMinor: rupees(3000),
  ),
];

/// Declares the contract tests in a group called [name]. [create] must return
/// a new, empty store each time; the suite closes it.
void ledgerStoreContract(String name, Future<LedgerStore> Function() create) {
  group('$name: LedgerStore contract', () {
    late LedgerStore store;

    setUp(() async => store = await create());
    tearDown(() async => store.close());

    group('entries', () {
      test('insert then read back equal', () async {
        final expense = _expense(
          250,
          DateTime(2026, 10, 5, 13, 45, 12, 345),
          note: 'Lunch, with a “quote” and ₹',
        );
        final income = _income(
          5000,
          DateTime(2026, 10, 6, 9),
          note: 'Freelance',
        );
        final uncategorised = _expense(
          75,
          DateTime(2026, 10, 7, 8),
          categoryId: null,
        );

        expect(await store.insertEntry(expense), expense);
        expect(await store.insertEntry(income), income);
        expect(await store.insertEntry(uncategorised), uncategorised);

        final read = await store.entriesForMonth(_oct);
        expect(read, [expense, income, uncategorised]);
        expect(read.first.note, 'Lunch, with a “quote” and ₹');
        expect(read[1].categoryId, isNull);
        expect(read[1].isIncome, isTrue);
        expect(read.first.source, EntrySource.manual);
      });

      test(
        'occurredAt comes back as a local DateTime, whole milliseconds',
        () async {
          final utc = DateTime.utc(2026, 10, 5, 8, 15, 12, 345, 678);
          final returned = await store.insertEntry(_expense(100, utc));
          expect(returned.occurredAt.isUtc, isFalse);
          expect(
            returned.occurredAt.millisecondsSinceEpoch,
            utc.millisecondsSinceEpoch,
          );
          expect(returned.occurredAt.microsecond, 0);

          final read = (await store.entriesForMonth(
            YearMonth.of(utc.toLocal()),
          )).single;
          expect(read, returned);
          expect(read.occurredAt.isUtc, isFalse);
          expect(read, storedForm(_expense(100, utc, id: returned.id)));
        },
      );

      test('entries come oldest first, then in insertion order', () async {
        final at = DateTime(2026, 10, 10, 12);
        final late = await store.insertEntry(
          _expense(1, DateTime(2026, 10, 20)),
        );
        final sameA = await store.insertEntry(_expense(2, at));
        final early = await store.insertEntry(
          _expense(3, DateTime(2026, 10, 2)),
        );
        final sameB = await store.insertEntry(_expense(4, at));
        final sameC = await store.insertEntry(_expense(5, at));
        expect(await store.entriesForMonth(_oct), [
          early,
          sameA,
          sameB,
          sameC,
          late,
        ]);
      });

      test('an id cannot be inserted twice', () async {
        final first = _expense(100, DateTime(2026, 10, 5), id: 'dup-$name');
        await store.insertEntry(first);
        await expectLater(
          store.insertEntry(
            _expense(999, DateTime(2026, 10, 6), id: 'dup-$name'),
          ),
          throwsA(anything),
        );
        expect(await store.entriesForMonth(_oct), [first]);
      });

      test('soft-deleted entries are not returned', () async {
        final keep = await store.insertEntry(
          _expense(100, DateTime(2026, 10, 5)),
        );
        final gone = await store.insertEntry(
          _expense(250, DateTime(2026, 10, 6)),
        );

        expect(await store.softDeleteEntry(gone.id), isTrue);
        expect(await store.entriesForMonth(_oct), [keep]);
      });

      test(
        'deleting an unknown id reports false and changes nothing',
        () async {
          final keep = await store.insertEntry(
            _expense(100, DateTime(2026, 10, 5)),
          );
          expect(await store.softDeleteEntry('no-such-id'), isFalse);
          expect(await store.entriesForMonth(_oct), [keep]);
        },
      );

      test('deleting twice reports false the second time, and the id stays '
          'taken', () async {
        final gone = await store.insertEntry(
          _expense(250, DateTime(2026, 10, 6)),
        );
        expect(await store.softDeleteEntry(gone.id), isTrue);
        expect(await store.softDeleteEntry(gone.id), isFalse);
        await expectLater(store.insertEntry(gone), throwsA(anything));
        expect(await store.entriesForMonth(_oct), isEmpty);
      });
    });

    group('month filtering at local month edges', () {
      test('first and last instant of the month are in; the instants either '
          'side are out', () async {
        const ms = Duration(milliseconds: 1);
        final first = await store.insertEntry(
          _expense(1, DateTime(2026, 10, 1)),
        );
        final last = await store.insertEntry(
          _expense(2, DateTime(2026, 11, 1).subtract(ms)),
        );
        final before = await store.insertEntry(
          _expense(3, DateTime(2026, 10, 1).subtract(ms)),
        );
        final after = await store.insertEntry(
          _expense(4, DateTime(2026, 11, 1)),
        );

        expect(last.occurredAt, DateTime(2026, 10, 31, 23, 59, 59, 999));
        expect(before.occurredAt, DateTime(2026, 9, 30, 23, 59, 59, 999));

        expect(await store.entriesForMonth(_oct), [first, last]);
        expect(await store.entriesForMonth(_sep), [before]);
        expect(await store.entriesForMonth(_nov), [after]);
        expect(await store.entriesForMonth(_dec), isEmpty);
      });

      test('ten past midnight on 1 November local counts toward November; '
          'ten to midnight on 31 October counts toward October', () async {
        final justAfter = await store.insertEntry(
          _expense(1, DateTime(2026, 11, 1, 0, 10)),
        );
        final justBefore = await store.insertEntry(
          _expense(2, DateTime(2026, 10, 31, 23, 50)),
        );
        expect(await store.entriesForMonth(_nov), [justAfter]);
        expect(await store.entriesForMonth(_oct), [justBefore]);
      });

      test('December and January are separate across the year end', () async {
        final december = await store.insertEntry(
          _expense(1, DateTime(2026, 12, 31, 23, 59, 59, 999)),
        );
        final january = await store.insertEntry(
          _expense(2, DateTime(2027, 1, 1)),
        );
        expect(await store.entriesForMonth(_dec), [december]);
        expect(await store.entriesForMonth(const YearMonth(2027, 1)), [
          january,
        ]);
        expect(await store.entriesForMonth(const YearMonth(2026, 1)), isEmpty);
      });
    });

    group('frequent expense amounts', () {
      test('none when nothing is recorded', () async {
        expect(await store.frequentExpenseAmounts(), isEmpty);
      });

      test('most frequent first, across every month', () async {
        final inserted = <Entry>[];
        Future<void> add(int amount, DateTime at) async =>
            inserted.add(await store.insertEntry(_expense(amount, at)));

        await add(100, DateTime(2026, 8, 1));
        await add(100, DateTime(2026, 9, 1));
        await add(100, DateTime(2026, 10, 1));
        await add(250, DateTime(2026, 10, 2));
        await add(250, DateTime(2026, 10, 3));
        await add(40, DateTime(2026, 10, 4));

        final amounts = await store.frequentExpenseAmounts();
        expect(amounts, [rupees(100), rupees(250), rupees(40)]);
        expect(amounts, frequentAmounts(inserted));
      });

      test(
        'ties go to the more recently used, then the later inserted',
        () async {
          final inserted = <Entry>[];
          Future<void> add(int amount, DateTime at) async =>
              inserted.add(await store.insertEntry(_expense(amount, at)));

          final sameMoment = DateTime(2026, 10, 9, 9);
          // 300 and 500 are each used twice; 500 was used more recently, though
          // 300 was inserted last.
          await add(500, DateTime(2026, 10, 1));
          await add(500, DateTime(2026, 10, 8));
          await add(300, DateTime(2026, 10, 2));
          await add(300, DateTime(2026, 10, 7));
          // 70 and 80 are each used once at the same moment; 80 went in later.
          await add(70, sameMoment);
          await add(80, sameMoment);
          // 60 is used once, earlier.
          await add(60, DateTime(2026, 9, 1));

          final amounts = await store.frequentExpenseAmounts();
          expect(amounts, [
            rupees(500),
            rupees(300),
            rupees(80),
            rupees(70),
            rupees(60),
          ]);
          expect(amounts, frequentAmounts(inserted));
        },
      );

      test('income and deleted entries are ignored', () async {
        await store.insertEntry(_income(999, DateTime(2026, 10, 1)));
        await store.insertEntry(_income(999, DateTime(2026, 10, 2)));
        await store.insertEntry(_income(999, DateTime(2026, 10, 3)));
        final a = await store.insertEntry(_expense(450, DateTime(2026, 10, 4)));
        final b = await store.insertEntry(_expense(450, DateTime(2026, 10, 5)));
        await store.insertEntry(_expense(120, DateTime(2026, 10, 1)));

        expect(await store.frequentExpenseAmounts(), [
          rupees(450),
          rupees(120),
        ]);

        // One 450 deleted: both amounts now count once and 120 is the older.
        await store.softDeleteEntry(b.id);
        expect(await store.frequentExpenseAmounts(), [
          rupees(450),
          rupees(120),
        ]);
        // Both deleted: 450 disappears.
        await store.softDeleteEntry(a.id);
        expect(await store.frequentExpenseAmounts(), [rupees(120)]);
      });

      test('a deleted use no longer decides a tie', () async {
        await store.insertEntry(_expense(200, DateTime(2026, 10, 1)));
        await store.insertEntry(_expense(300, DateTime(2026, 10, 2)));
        final recent200 = await store.insertEntry(
          _expense(200, DateTime(2026, 10, 3)),
        );
        await store.insertEntry(_expense(300, DateTime(2026, 9, 1)));
        // 200: 1 and 3 October. 300: 2 October and 1 September.
        expect(await store.frequentExpenseAmounts(), [
          rupees(200),
          rupees(300),
        ]);
        await store.softDeleteEntry(recent200.id);
        expect(await store.frequentExpenseAmounts(), [
          rupees(300),
          rupees(200),
        ]);
      });

      test('at most the number asked for, five by default', () async {
        for (var i = 1; i <= 8; i++) {
          await store.insertEntry(_expense(i * 10, DateTime(2026, 10, i)));
        }
        expect(await store.frequentExpenseAmounts(), [
          rupees(80),
          rupees(70),
          rupees(60),
          rupees(50),
          rupees(40),
        ]);
        expect(await store.frequentExpenseAmounts(limit: 2), [
          rupees(80),
          rupees(70),
        ]);
        expect(await store.frequentExpenseAmounts(limit: 0), isEmpty);
      });
    });

    group('budgets', () {
      test('an empty store reports no budget', () async {
        expect(await store.hasAnyBudget(), isFalse);
        expect(await store.budgetFor(_oct), isNull);
      });

      test(
        'a month with nothing set carries the earlier budget forward',
        () async {
          await store.setBudget(_oct, rupees(30000));
          expect(await store.hasAnyBudget(), isTrue);
          expect(await store.budgetFor(_oct), rupees(30000));
          expect(await store.budgetFor(_nov), rupees(30000));
          expect(
            await store.budgetFor(const YearMonth(2027, 2)),
            rupees(30000),
          );
          expect(await store.budgetFor(_sep), isNull);
        },
      );

      test('setting one month leaves the others alone', () async {
        await store.setBudget(_oct, rupees(30000));
        await store.setBudget(_nov, rupees(32000));
        expect(await store.budgetFor(_oct), rupees(30000));
        expect(await store.budgetFor(_nov), rupees(32000));
        expect(await store.budgetFor(_dec), rupees(32000));
      });

      test('setting a month again replaces its budget', () async {
        await store.setBudget(_oct, rupees(30000));
        await store.setBudget(_oct, rupees(15000));
        expect(await store.budgetFor(_oct), rupees(15000));
        expect(await store.budgetFor(_nov), rupees(15000));
      });

      test('carry-forward crosses a year boundary in calendar order', () async {
        await store.setBudget(_dec, rupees(30000));
        await store.setBudget(const YearMonth(2026, 2), rupees(20000));
        expect(await store.budgetFor(const YearMonth(2027, 1)), rupees(30000));
        expect(await store.budgetFor(const YearMonth(2026, 11)), rupees(20000));
        expect(await store.budgetFor(const YearMonth(2025, 12)), isNull);
      });
    });

    group('categories', () {
      test('an empty store has none', () async {
        expect(await store.loadCategories(), isEmpty);
      });

      test('come back equal and in the order given', () async {
        await store.replaceCategories(_categories);
        expect(await store.loadCategories(), _categories);

        final reversed = _categories.reversed.toList();
        await store.replaceCategories(reversed);
        expect(await store.loadCategories(), reversed);
      });

      test('saving a limit changes that category only', () async {
        await store.replaceCategories(_categories);
        expect(await store.saveCategoryLimit('food', rupees(8000)), isTrue);
        final loaded = await store.loadCategories();
        expect(loaded.map((c) => c.id), ['food', 'bills', 'travel']);
        expect(loaded[0].limitMinor, rupees(8000));
        expect(loaded[0].name, 'Food');
        expect(loaded[0].colorValue, 0xFFF2B880);
        expect(loaded.sublist(1), _categories.sublist(1));
      });

      test('saving a limit for an unknown category reports false', () async {
        await store.replaceCategories(_categories);
        expect(await store.saveCategoryLimit('pets', rupees(500)), isFalse);
        expect(await store.loadCategories(), _categories);
      });

      test('replacing drops categories left out, updates the rest, and can '
          'bring one back', () async {
        await store.replaceCategories(_categories);
        final entry = await store.insertEntry(
          _expense(120, DateTime(2026, 10, 3), categoryId: 'bills'),
        );
        final fewer = [
          Category(
            id: 'travel',
            name: 'Trips',
            colorValue: 0xFF000001,
            limitMinor: rupees(1),
          ),
          Category(
            id: 'pets',
            name: 'Pets',
            colorValue: 0xFF000002,
            limitMinor: rupees(900),
          ),
        ];
        await store.replaceCategories(fewer);
        expect(await store.loadCategories(), fewer);
        expect(await store.saveCategoryLimit('bills', rupees(1)), isFalse);
        // Entries filed to a dropped category keep its id.
        expect(await store.entriesForMonth(_oct), [entry]);

        await store.replaceCategories(_categories);
        expect(await store.loadCategories(), _categories);
      });

      test(
        'two categories with one id are refused and nothing changes',
        () async {
          await store.replaceCategories(_categories);
          await expectLater(
            store.replaceCategories([_categories[0], _categories[0]]),
            throwsA(anything),
          );
          expect(await store.loadCategories(), _categories);
        },
      );
    });

    group('profile', () {
      test('an empty store has none', () async {
        expect(await store.loadProfile(), isNull);
      });

      test('round trip', () async {
        final profile = Profile(monthlyIncomeMinor: rupees(45000));
        await store.saveProfile(profile);
        expect(await store.loadProfile(), profile);
        expect((await store.loadProfile())!.homeCurrency, 'INR');
      });

      test('saving again replaces it', () async {
        await store.saveProfile(Profile(monthlyIncomeMinor: rupees(45000)));
        final next = Profile(
          monthlyIncomeMinor: rupees(9999999),
          homeCurrency: 'USD',
        );
        await store.saveProfile(next);
        expect(await store.loadProfile(), next);
      });

      test('income is not an entry and does not create a budget', () async {
        await store.saveProfile(Profile(monthlyIncomeMinor: rupees(45000)));
        expect(await store.hasAnyBudget(), isFalse);
        expect(await store.entriesForMonth(_oct), isEmpty);
      });
    });

    group('budget settings saved together', () {
      final profile = Profile(monthlyIncomeMinor: rupees(45000));

      test('income, a month\'s budget and limits are all saved', () async {
        await store.replaceCategories(_categories);
        await store.setBudget(_sep, rupees(30000));

        await store.saveBudgetSettings(
          profile: profile,
          categoryLimits: {'food': rupees(8000), 'travel': rupees(2500)},
          budget: (month: _oct, totalMinor: rupees(32000)),
        );

        expect(await store.loadProfile(), profile);
        expect(await store.budgetFor(_oct), rupees(32000));
        // The earlier month keeps its own budget.
        expect(await store.budgetFor(_sep), rupees(30000));
        final loaded = await store.loadCategories();
        expect(loaded.map((c) => c.id), ['food', 'bills', 'travel']);
        expect(loaded.map((c) => c.limitMinor), [
          rupees(8000),
          rupees(10500),
          rupees(2500),
        ]);
        expect(loaded[0].name, 'Food');
      });

      test('what is left out is left as it is', () async {
        await store.replaceCategories(_categories);
        await store.saveProfile(profile);
        await store.setBudget(_oct, rupees(30000));

        await store.saveBudgetSettings(
          budget: (month: _oct, totalMinor: rupees(32000)),
        );
        expect(await store.budgetFor(_oct), rupees(32000));
        expect(await store.loadCategories(), _categories);
        expect(await store.loadProfile(), profile);

        await store.saveBudgetSettings(categoryLimits: {'food': rupees(8000)});
        expect(await store.budgetFor(_oct), rupees(32000));
        expect(await store.loadProfile(), profile);
        expect((await store.loadCategories()).first.limitMinor, rupees(8000));

        await store.saveBudgetSettings();
        expect(await store.budgetFor(_oct), rupees(32000));
      });

      test('categories, income and the first budget in one go, with limits '
          'applied to the new categories', () async {
        await store.saveBudgetSettings(
          profile: profile,
          categories: _categories,
          categoryLimits: {'bills': rupees(11000)},
          budget: (month: _oct, totalMinor: rupees(30000)),
        );

        expect(await store.hasAnyBudget(), isTrue);
        expect(await store.budgetFor(_oct), rupees(30000));
        expect(await store.loadProfile(), profile);
        final loaded = await store.loadCategories();
        expect(loaded.map((c) => c.id), ['food', 'bills', 'travel']);
        expect(loaded[1].limitMinor, rupees(11000));
        expect([loaded[0], loaded[2]], [_categories[0], _categories[2]]);
      });

      test('a failure part-way leaves nothing changed', () async {
        await store.replaceCategories(_categories);
        await store.saveProfile(profile);
        await store.setBudget(_oct, rupees(30000));

        // The income and Food's limit could be saved; the limit after them
        // is for a category that does not exist.
        await expectLater(
          store.saveBudgetSettings(
            profile: Profile(monthlyIncomeMinor: rupees(50000)),
            categoryLimits: {'food': rupees(8000), 'pets': rupees(500)},
            budget: (month: _oct, totalMinor: rupees(32000)),
          ),
          throwsA(anything),
        );

        expect(await store.loadProfile(), profile);
        expect(await store.loadCategories(), _categories);
        expect(await store.budgetFor(_oct), rupees(30000));
      });

      test('a refused set of categories leaves nothing changed, and setup '
          'stays incomplete', () async {
        await expectLater(
          store.saveBudgetSettings(
            profile: profile,
            categories: [_categories[0], _categories[0]],
            budget: (month: _oct, totalMinor: rupees(30000)),
          ),
          throwsA(anything),
        );

        expect(await store.loadProfile(), isNull);
        expect(await store.loadCategories(), isEmpty);
        expect(await store.hasAnyBudget(), isFalse);
      });
    });
  });
}
