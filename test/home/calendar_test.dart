// The "Figures follow the calendar" requirement of the monthly-budget spec.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide/budget/budget.dart';
import 'package:tide/state/budget_state.dart';
import 'package:tide/storage/storage.dart';

import '../support/failing_ledger_store.dart';
import '../support/log_helpers.dart';
import '../support/pump_home.dart';

class _CountingStore extends FailingLedgerStore {
  _CountingStore({super.inner});

  final List<YearMonth> monthsRead = [];
  bool failReads = false;

  @override
  Future<List<Entry>> entriesForMonth(YearMonth month) async {
    monthsRead.add(month);
    if (failReads) throw const LedgerStoreFailure('entriesForMonth');
    return super.entriesForMonth(month);
  }
}

void main() {
  const oct = YearMonth(2026, 10);
  const nov = YearMonth(2026, 11);

  /// Moves the clock and the app's timers on together, then lets the month
  /// load and the screen rebuild.
  Future<void> pass(LogHarness app, Duration d) async {
    app.clock.advance(d);
    await app.tester.pump(d);
    await app.tester.pump();
  }

  Future<void> background(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
  }

  Future<void> foreground(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
  }

  void expectNoSpend(LogHarness app) {
    expect(app.entries, isEmpty);
    expect(app.snapshot.categories, hasLength(6));
    expect(app.snapshot.categories.every((c) => c.spentMinor == 0), isTrue);
    expect(find.text('₹0'), findsNWidgets(6));
  }

  testWidgets('midnight at month end: as 31 October becomes 1 November the '
      'screen shows November, ₹30,000 remaining and every category at ₹0', (
    tester,
  ) async {
    final app = await pumpLogApp(
      tester,
      start: DateTime(2026, 10, 31, 23, 59, 30),
    );
    expect(find.text('October'), findsOneWidget);
    expect(find.text('₹13,601'), findsOneWidget);
    expect(find.text('left of ₹30,000'), findsOneWidget);

    await pass(app, const Duration(seconds: 29));
    expect(find.text('October'), findsOneWidget);

    await pass(app, const Duration(seconds: 1));
    expect(find.text('November'), findsOneWidget);
    expect(find.text('October'), findsNothing);
    expect(find.text('₹30,000'), findsOneWidget);
    expect(find.text('left of ₹30,000'), findsOneWidget);
    expect(find.text('100% full'), findsOneWidget);
    expect(find.text('Safe today: ₹1,000'), findsOneWidget);
    expectNoSpend(app);
    final state = containerOf(tester).read(budgetProvider);
    expect(state.month, nov);
    expect(state.budgetMinor, rupees(30000));

    // October is still in the ledger, and November's budget was not written.
    expect(await app.store.entriesForMonth(oct), hasLength(12));
    expect(await app.store.budgetFor(nov), rupees(30000));

    // What is logged now belongs to November.
    await app.log('250', 'food');
    expect(app.snapshot.remainingMinor, rupees(29750));
    expect(await app.store.entriesForMonth(nov), hasLength(1));
  });

  testWidgets('returning after a few days: last used on 30 October, brought '
      'back on 2 November, the screen shows November\'s figures', (
    tester,
  ) async {
    final store = _CountingStore(
      inner: MemoryLedgerStore.sampleMonth(DateTime(2026, 10, 30, 18)),
    );
    final app = await pumpLogApp(
      tester,
      start: DateTime(2026, 10, 30, 18),
      store: store,
    );
    expect(find.text('October'), findsOneWidget);
    expect(find.text('₹13,601'), findsOneWidget);
    expect(store.monthsRead, [oct]);

    await background(tester);
    app.clock.now = DateTime(2026, 11, 2, 8);
    await foreground(tester);

    expect(find.text('November'), findsOneWidget);
    expect(find.text('₹30,000'), findsOneWidget);
    expect(find.text('left of ₹30,000'), findsOneWidget);
    expect(find.text('100% full'), findsOneWidget);
    expectNoSpend(app);
    expect(store.monthsRead, [oct, nov]);
  });

  testWidgets('the new month\'s entries and budget come from the store', (
    tester,
  ) async {
    final store = MemoryLedgerStore.sampleMonth(DateTime(2026, 10, 30, 18));
    final app = await pumpLogApp(
      tester,
      start: DateTime(2026, 10, 30, 18),
      store: store,
    );
    // Already in the ledger for November, though not in memory.
    await store.setBudget(nov, rupees(32000));
    final rent = await store.insertEntry(
      Entry(
        id: 'nov-rent',
        type: EntryType.expense,
        amountMinor: rupees(8000),
        categoryId: 'bills',
        occurredAt: DateTime(2026, 11, 1, 9),
      ),
    );
    await tester.pump();
    expect(find.text('₹13,601'), findsOneWidget);

    await background(tester);
    app.clock.now = DateTime(2026, 11, 2, 8);
    await foreground(tester);

    expect(find.text('November'), findsOneWidget);
    expect(app.entries, [rent]);
    expect(find.text('₹24,000'), findsOneWidget);
    expect(find.text('left of ₹32,000'), findsOneWidget);
    expect(app.snapshot.categoryById('bills')!.spentMinor, rupees(8000));
    expect(await store.budgetFor(oct), rupees(30000));
  });

  testWidgets('when only the day changes, safe-to-spend changes and nothing '
      'is reloaded', (tester) async {
    final store = _CountingStore(
      inner: MemoryLedgerStore.sampleMonth(DateTime(2026, 10, 5, 23, 59, 30)),
    );
    final app = await pumpLogApp(
      tester,
      start: DateTime(2026, 10, 5, 23, 59, 30),
      store: store,
    );
    // ₹13,601 over the 27 days from the 5th to the 31st.
    expect(find.text('Safe today: ₹503'), findsOneWidget);
    expect(app.snapshot.daysLeft, 27);

    await pass(app, const Duration(seconds: 30));

    // Over 26 days.
    expect(find.text('Safe today: ₹523'), findsOneWidget);
    expect(app.snapshot.daysLeft, 26);
    expect(find.text('October'), findsOneWidget);
    expect(find.text('₹13,601'), findsOneWidget);
    expect(app.entries, hasLength(12));
    expect(store.monthsRead, [oct]);
  });

  testWidgets('a day that changes while the app is away is caught on '
      'return', (tester) async {
    final app = await pumpLogApp(tester, start: DateTime(2026, 10, 5, 10));
    expect(find.text('Safe today: ₹503'), findsOneWidget);

    await background(tester);
    app.clock.now = DateTime(2026, 10, 8, 7);
    await foreground(tester);

    // ₹13,601 over the 24 days from the 8th to the 31st.
    expect(find.text('Safe today: ₹566'), findsOneWidget);
  });

  testWidgets('if the new month cannot be read the old figures stay, and '
      'the next return tries again', (tester) async {
    final store = _CountingStore(
      inner: MemoryLedgerStore.sampleMonth(DateTime(2026, 10, 30, 18)),
    );
    final app = await pumpLogApp(
      tester,
      start: DateTime(2026, 10, 30, 18),
      store: store,
    );

    store.failReads = true;
    await background(tester);
    app.clock.now = DateTime(2026, 11, 2, 8);
    await foreground(tester);
    // Not November with October's budget and nothing spent: still October.
    expect(find.text('October'), findsOneWidget);
    expect(find.text('₹13,601'), findsOneWidget);
    expect(app.entries, hasLength(12));

    store.failReads = false;
    await background(tester);
    app.clock.now = DateTime(2026, 11, 3, 8);
    await foreground(tester);
    expect(find.text('November'), findsOneWidget);
    expect(find.text('₹30,000'), findsOneWidget);
    expectNoSpend(app);
  });
}
