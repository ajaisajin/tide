import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide/budget/budget.dart';
import 'package:tide/budget_screen/budget_screen.dart';
import 'package:tide/home/confirmation_toast.dart';
import 'package:tide/home/home_screen.dart';
import 'package:tide/home/log_flow_state.dart';
import 'package:tide/home/pull_to_log.dart';
import 'package:tide/log/log_flow.dart';
import 'package:tide/log/number_pad.dart';
import 'package:tide/setup/budget_vessel.dart';
import 'package:tide/state/budget_state.dart';
import 'package:tide/state/confirmation_state.dart';
import 'package:tide/state/seed.dart';
import 'package:tide/storage/storage.dart';
import 'package:tide/vessel/vessel_layer.dart';

import '../support/failing_ledger_store.dart';
import '../support/gated_ledger_store.dart';
import '../support/log_helpers.dart';
import '../support/pump_home.dart';

/// The sample month with an income of ₹45,000: ₹13,601 left of ₹30,000,
/// ₹16,399 spent, Food at ₹2,330 of ₹6,000, limits adding up to ₹25,000.
MemoryLedgerStore sampleLedger() => MemoryLedgerStore.sampleMonth(
  oct5,
  profile: Profile(monthlyIncomeMinor: rupees(45000)),
);

/// The app on [store] with the real log flow, and the budget screen driven
/// as a user drives it.
class BudgetHarness {
  BudgetHarness(this.tester, this.app);

  final WidgetTester tester;
  final LogHarness app;

  BudgetState get state => containerOf(tester).read(budgetProvider);
  bool get isOpen => containerOf(tester).read(budgetScreenOpenProvider);

  Future<void> open() async {
    await tester.tap(find.byKey(VesselLayer.budgetLineKey));
    await app.settle();
    expect(find.byType(BudgetScreen), findsOneWidget);
  }

  /// Types [rupeeAmount] as the budget on the vessel's own pad.
  Future<void> typeBudget(int rupeeAmount) async {
    await tester.tap(find.byKey(BudgetVessel.budgetKey));
    await tester.pump();
    await app.type('$rupeeAmount');
    await tester.tap(find.byKey(BudgetVessel.typedDoneKey));
    await tester.pump();
  }

  /// Opens the pad from the row [row] and types [rupeeAmount], without Done.
  Future<void> startTyping(Key row, int rupeeAmount) async {
    await tester.ensureVisible(find.byKey(row));
    await tester.pump();
    await tester.tap(find.byKey(row));
    await tester.pump();
    await app.type('$rupeeAmount');
  }

  Future<void> typeInto(Key row, int rupeeAmount) async {
    await startTyping(row, rupeeAmount);
    await tester.tap(find.byKey(BudgetScreen.typedDoneKey));
    await tester.pump();
  }

  Future<void> typeLimit(String categoryId, int rupeeAmount) =>
      typeInto(BudgetScreen.limitKey(categoryId), rupeeAmount);

  Future<void> typeIncome(int rupeeAmount) =>
      typeInto(BudgetScreen.incomeKey, rupeeAmount);

  Future<void> tapSave() async {
    await tester.ensureVisible(find.byKey(BudgetScreen.saveKey));
    await tester.pump();
    await tester.tap(find.byKey(BudgetScreen.saveKey));
    await app.settle();
  }

  Future<void> tapCancel() async {
    await tester.ensureVisible(find.byKey(BudgetScreen.cancelKey));
    await tester.pump();
    await tester.tap(find.byKey(BudgetScreen.cancelKey));
    await app.settle();
  }

  /// The amount a row shows.
  String rowAmount(Key row) => tester
      .widgetList<Text>(
        find.descendant(of: find.byKey(row), matching: find.byType(Text)),
      )
      .last
      .data!;

  String limitText(String categoryId) =>
      rowAmount(BudgetScreen.limitKey(categoryId));

  String get budgetText =>
      tester.widget<Text>(find.byKey(BudgetVessel.budgetKey)).data!;

  String get remainingText =>
      tester.widget<Text>(find.byKey(VesselLayer.remainingKey)).data!;
}

Future<BudgetHarness> pumpBudgetApp(
  WidgetTester tester, {
  LedgerStore? store,
  Size size = const Size(412, 915),
  double textScale = 1,
}) async {
  final app = await pumpLogApp(
    tester,
    store: store ?? sampleLedger(),
    size: size,
    textScale: textScale,
  );
  return BudgetHarness(tester, app);
}

void main() {
  group('opening the budget screen from home', () {
    testWidgets('the budget line is a button with a semantic label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpBudgetApp(tester);

      final line = find.bySemanticsLabel(VesselLayer.budgetLineLabel);
      expect(line, findsOneWidget);
      final data = tester.getSemantics(line).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(
        find.descendant(
          of: find.byKey(VesselLayer.budgetLineKey),
          matching: find.text('left of ₹30,000'),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('Opening: tapping the budget line opens the budget screen in '
        'the overlay slot, showing the saved income, budget and six limits', (
      tester,
    ) async {
      final b = await pumpBudgetApp(tester);
      expect(find.byKey(HomeScreen.overlaySlotKey), findsNothing);

      await b.open();

      expect(
        find.descendant(
          of: find.byKey(HomeScreen.overlaySlotKey),
          matching: find.byType(BudgetScreen),
        ),
        findsOneWidget,
      );
      expect(find.byType(LogFlow), findsNothing);
      expect(b.budgetText, '₹30,000');
      expect(find.text('of ₹45,000 income'), findsOneWidget);
      expect(find.text('₹15,000 set aside'), findsOneWidget);
      expect(b.rowAmount(BudgetScreen.incomeKey), '₹45,000');
      expect(
        {for (final c in seedCategories) c.name: b.limitText(c.id)},
        {
          'Food': '₹6,000',
          'Bills': '₹11,000',
          'Travel': '₹3,000',
          'Shopping': '₹2,000',
          'Fun': '₹1,500',
          'Health': '₹1,500',
        },
      );
      for (final c in seedCategories) {
        expect(
          find.descendant(
            of: find.byKey(BudgetScreen.limitKey(c.id)),
            matching: find.text(c.name),
          ),
          findsOneWidget,
        );
      }
      expect(
        tester.widget<Text>(find.byKey(BudgetScreen.limitsTotalKey)).data,
        '₹25,000',
      );
      expect(find.byKey(BudgetScreen.overBudgetKey), findsNothing);
    });

    testWidgets('the semantic action on the budget line opens it too', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final b = await pumpBudgetApp(tester);

      tester.semantics.tap(find.semantics.byLabel(VesselLayer.budgetLineLabel));
      await b.app.settle();

      expect(find.byType(BudgetScreen), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the pull-down still opens the log flow, not the budget '
        'screen', (tester) async {
      final b = await pumpBudgetApp(tester);

      await tester.dragFrom(const Offset(206, 500), const Offset(0, 120));
      await b.app.settle();

      expect(find.byType(LogFlow), findsOneWidget);
      expect(find.byType(BudgetScreen), findsNothing);
      expect(b.isOpen, isFalse);
    });

    testWidgets('a pull-down that starts on the budget line opens the log '
        'flow', (tester) async {
      final b = await pumpBudgetApp(tester);

      await tester.dragFrom(
        tester.getCenter(find.byKey(VesselLayer.budgetLineKey)),
        const Offset(0, 120),
      );
      await b.app.settle();

      expect(find.byType(LogFlow), findsOneWidget);
      expect(find.byType(BudgetScreen), findsNothing);
    });

    testWidgets('the handle still opens the log flow, not the budget screen', (
      tester,
    ) async {
      final b = await pumpBudgetApp(tester);

      await tester.tap(find.byKey(LogHandle.handleKey));
      await b.app.settle();

      expect(find.byType(LogFlow), findsOneWidget);
      expect(find.byType(BudgetScreen), findsNothing);
      expect(b.isOpen, isFalse);
    });

    testWidgets('the log flow opens as before once the budget screen has '
        'been closed', (tester) async {
      final b = await pumpBudgetApp(tester);
      await b.open();
      await b.tapCancel();
      expect(find.byType(BudgetScreen), findsNothing);

      await b.app.log('250', 'food');

      expect(find.text('Logged ₹250 to Food · 0.0 s'), findsOneWidget);
      expect(b.remainingText, '₹13,351');
    });

    testWidgets('with no income saved the budget cannot be changed until an '
        'income is set, and nothing is made up', (tester) async {
      final store = MemoryLedgerStore.sampleMonth(oct5);
      final b = await pumpBudgetApp(tester, store: store);
      await b.open();

      expect(find.byType(BudgetVessel), findsNothing);
      expect(b.budgetText, '₹30,000');
      expect(find.text(BudgetScreen.noIncomeMessage), findsOneWidget);
      expect(b.rowAmount(BudgetScreen.incomeKey), 'Not set');

      await b.typeIncome(45000);
      expect(find.byType(BudgetVessel), findsOneWidget);
      expect(find.text('₹15,000 set aside'), findsOneWidget);

      await b.tapSave();
      expect((await store.loadProfile())!.monthlyIncomeMinor, rupees(45000));
      expect(b.state.budgetMinor, rupees(30000));
    });
  });

  group('changing the budget and income', () {
    testWidgets('Raising the budget mid-month: ₹13,601 of ₹30,000, save '
        '₹32,000, and home shows ₹15,601 "left of ₹32,000"', (tester) async {
      final store = sampleLedger();
      final b = await pumpBudgetApp(tester, store: store);
      expect(b.remainingText, '₹13,601');
      expect(find.text('left of ₹30,000'), findsOneWidget);

      await b.open();
      await b.typeBudget(32000);
      expect(b.budgetText, '₹32,000');
      await b.tapSave();

      expect(find.byType(BudgetScreen), findsNothing);
      expect(b.remainingText, '₹15,601');
      expect(find.text('left of ₹32,000'), findsOneWidget);
      expect(find.text('left of ₹30,000'), findsNothing);
      expect(find.text(BudgetScreen.savedNotice), findsOneWidget);
      expect(find.byKey(ConfirmationToast.undoKey), findsNothing);
      expect(await store.budgetFor(const YearMonth(2026, 10)), rupees(32000));
    });

    testWidgets('dragging the vessel changes the budget in steps, and saving '
        'it updates home', (tester) async {
      final b = await pumpBudgetApp(tester);
      await b.open();

      // The top of the tank is a full vessel: the whole income.
      final tank = tester.getRect(find.byKey(BudgetVessel.tankKey));
      await tester.dragFrom(
        tank.center,
        Offset(0, tank.top - tank.center.dy - 40),
      );
      await tester.pump();
      expect(b.budgetText, '₹45,000');
      expect(find.text('₹0 set aside'), findsOneWidget);

      await b.tapSave();
      expect(find.text('left of ₹45,000'), findsOneWidget);
    });

    testWidgets('Lowering the budget below what is spent: ₹16,399 spent, '
        'save ₹15,000, and home shows the overspent state at −₹1,399', (
      tester,
    ) async {
      final b = await pumpBudgetApp(tester);
      expect(b.app.snapshot.spentMinor, rupees(16399));

      await b.open();
      await b.typeBudget(15000);
      await b.tapSave();

      expect(b.remainingText, '−₹1,399');
      expect(b.app.snapshot.isOverspent, isTrue);
      expect(b.app.snapshot.band, StatusBand.belowTheLine);
      expect(find.text('over your ₹15,000'), findsOneWidget);
      expect(find.text('Below the line'), findsOneWidget);
    });

    testWidgets('Leaving without saving: a changed budget, income and limit '
        'are dropped by Cancel and home is unchanged', (tester) async {
      final store = sampleLedger();
      final b = await pumpBudgetApp(tester, store: store);
      final before = b.state;

      await b.open();
      await b.typeBudget(32000);
      await b.typeIncome(50000);
      await b.typeLimit('food', 8000);
      await b.tapCancel();

      expect(find.byType(BudgetScreen), findsNothing);
      expect(b.state, same(before));
      expect(b.remainingText, '₹13,601');
      expect(find.text('left of ₹30,000'), findsOneWidget);
      expect(containerOf(tester).read(confirmationProvider), isNull);
      expect(await store.budgetFor(const YearMonth(2026, 10)), rupees(30000));
      expect((await store.loadProfile())!.monthlyIncomeMinor, rupees(45000));
      expect(await store.loadCategories(), seedCategories);

      // Opening again starts from what is saved, not from what was dropped.
      await b.open();
      expect(b.budgetText, '₹30,000');
      expect(b.rowAmount(BudgetScreen.incomeKey), '₹45,000');
      expect(b.limitText('food'), '₹6,000');
    });

    testWidgets('the system back button behaves as Cancel', (tester) async {
      final store = sampleLedger();
      final b = await pumpBudgetApp(tester, store: store);
      final before = b.state;
      await b.open();
      await b.typeBudget(32000);

      await tester.binding.handlePopRoute();
      await b.app.settle();

      expect(find.byType(BudgetScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(b.isOpen, isFalse);
      expect(b.state, same(before));
      expect(b.remainingText, '₹13,601');
      expect(find.text('left of ₹30,000'), findsOneWidget);
      expect(await store.budgetFor(const YearMonth(2026, 10)), rupees(30000));
    });

    testWidgets('the system back button behaves as Cancel while an amount is '
        'being typed', (tester) async {
      final b = await pumpBudgetApp(tester);
      final before = b.state;
      await b.open();
      await b.startTyping(BudgetScreen.limitKey('food'), 8000);

      await tester.binding.handlePopRoute();
      await b.app.settle();

      expect(find.byType(BudgetScreen), findsNothing);
      expect(b.state, same(before));
    });

    testWidgets('a typed budget is not saved until its own Done: Save waits '
        'while the vessel\'s pad is open', (tester) async {
      final store = GatedLedgerStore(inner: sampleLedger());
      final b = await pumpBudgetApp(tester, store: store);
      await b.open();

      await tester.tap(find.byKey(BudgetVessel.budgetKey));
      await tester.pump();
      await b.app.type('32000');
      await b.tapSave();

      expect(store.settingsSaves, 0);
      expect(find.byType(BudgetScreen), findsOneWidget);

      await tester.tap(find.byKey(BudgetVessel.typedDoneKey));
      await tester.pump();
      await b.tapSave();
      expect(store.settingsSaves, 1);
      expect(b.state.budgetMinor, rupees(32000));
    });

    testWidgets('a budget of ₹0 cannot be saved, and the screen says why', (
      tester,
    ) async {
      final store = GatedLedgerStore(inner: sampleLedger());
      final b = await pumpBudgetApp(tester, store: store);
      await b.open();

      final tank = tester.getRect(find.byKey(BudgetVessel.tankKey));
      await tester.dragFrom(tank.center, Offset(0, tank.height));
      await tester.pump();
      expect(b.budgetText, '₹0');
      expect(find.text(BudgetScreen.noBudgetMessage), findsOneWidget);

      await b.tapSave();
      expect(store.settingsSaves, 0);
      expect(find.byType(BudgetScreen), findsOneWidget);
      expect(b.state.budgetMinor, rupees(30000));
    });

    testWidgets('saving a new income keeps the budget; an income below the '
        'budget brings the budget down to it', (tester) async {
      final store = sampleLedger();
      final b = await pumpBudgetApp(tester, store: store);
      await b.open();

      await b.typeIncome(60000);
      expect(b.rowAmount(BudgetScreen.incomeKey), '₹60,000');
      expect(b.budgetText, '₹30,000');
      expect(find.text('₹30,000 set aside'), findsOneWidget);

      await b.typeIncome(20000);
      expect(b.budgetText, '₹20,000');
      expect(find.text('₹0 set aside'), findsOneWidget);

      await b.tapSave();
      expect(b.state.incomeMinor, rupees(20000));
      expect(b.state.budgetMinor, rupees(20000));
      expect(find.text('left of ₹20,000'), findsOneWidget);
      expect((await store.loadProfile())!.monthlyIncomeMinor, rupees(20000));
      // Income is a reference figure: it is not an entry.
      expect(b.app.entries, hasLength(12));
    });

    testWidgets('an income is accepted from ₹1 to ₹99,99,999 only', (
      tester,
    ) async {
      final b = await pumpBudgetApp(tester);
      await b.open();

      await b.typeIncome(0);
      expect(
        find.text(BudgetScreen.belowMinimumMessage('Monthly income')),
        findsOneWidget,
      );
      // An eighth digit is not taken.
      await b.app.type('99999999');
      expect(
        tester.widget<Text>(find.byKey(BudgetScreen.typedAmountKey)).data,
        '₹99,99,999',
      );
      await tester.tap(find.byKey(BudgetScreen.typedDoneKey));
      await tester.pump();
      expect(b.rowAmount(BudgetScreen.incomeKey), '₹99,99,999');
    });

    testWidgets('changing the budget leaves an earlier month\'s budget as it '
        'was', (tester) async {
      final store = MemoryLedgerStore(
        categories: seedCategories,
        budgets: {const YearMonth(2026, 9): rupees(30000)},
        profile: Profile(monthlyIncomeMinor: rupees(45000)),
      );
      final b = await pumpBudgetApp(tester, store: store);
      expect(find.text('left of ₹30,000'), findsOneWidget);

      await b.open();
      await b.typeBudget(32000);
      await b.tapSave();

      expect(find.text('left of ₹32,000'), findsOneWidget);
      expect(await store.budgetFor(const YearMonth(2026, 10)), rupees(32000));
      expect(await store.budgetFor(const YearMonth(2026, 9)), rupees(30000));
    });
  });

  group('changing a category\'s limit', () {
    testWidgets('Raising a limit: Food has ₹2,330 of ₹6,000, save ₹8,000, '
        'and Food\'s pebble reflects ₹2,330 of ₹8,000', (tester) async {
      final handle = tester.ensureSemantics();
      final store = sampleLedger();
      final b = await pumpBudgetApp(tester, store: store);
      expect(find.bySemanticsLabel('Food, ₹2,330 of ₹6,000'), findsOneWidget);

      await b.open();
      await b.typeLimit('food', 8000);
      expect(b.limitText('food'), '₹8,000');
      await b.tapSave();

      expect(find.bySemanticsLabel('Food, ₹2,330 of ₹8,000'), findsOneWidget);
      expect(find.bySemanticsLabel('Food, ₹2,330 of ₹6,000'), findsNothing);
      final food = b.app.snapshot.categories.firstWhere(
        (c) => c.category.id == 'food',
      );
      expect(food.spentMinor, rupees(2330));
      expect(food.category.limitMinor, rupees(8000));
      expect((await store.loadCategories()).first.limitMinor, rupees(8000));
      // The others, and the budget, are as they were.
      expect(b.state.categories.skip(1), seedCategories.skip(1));
      expect(b.state.budgetMinor, rupees(30000));
      handle.dispose();
    });

    testWidgets('Limits add up to more than the budget: ₹34,000 against '
        '₹30,000 says ₹4,000 more, and saving is still allowed', (
      tester,
    ) async {
      final store = sampleLedger();
      final b = await pumpBudgetApp(tester, store: store);
      await b.open();
      expect(find.byKey(BudgetScreen.overBudgetKey), findsNothing);

      // ₹25,000 with Food at ₹6,000; ₹34,000 with Food at ₹15,000.
      await b.typeLimit('food', 15000);

      expect(
        tester.widget<Text>(find.byKey(BudgetScreen.limitsTotalKey)).data,
        '₹34,000',
      );
      expect(
        tester.widget<Text>(find.byKey(BudgetScreen.overBudgetKey)).data,
        '₹4,000 more than the budget',
      );

      await b.tapSave();
      expect(find.byType(BudgetScreen), findsNothing);
      expect(b.state.categories.first.limitMinor, rupees(15000));
      expect((await store.loadCategories()).first.limitMinor, rupees(15000));
    });

    testWidgets('the note follows the budget as well as the limits', (
      tester,
    ) async {
      final b = await pumpBudgetApp(tester);
      await b.open();

      await b.typeBudget(24000);
      expect(
        tester.widget<Text>(find.byKey(BudgetScreen.overBudgetKey)).data,
        '₹1,000 more than the budget',
      );
      await b.typeBudget(25000);
      expect(find.byKey(BudgetScreen.overBudgetKey), findsNothing);
    });

    testWidgets('Category limits untouched: changing the budget from ₹30,000 '
        'to ₹32,000 leaves Food\'s limit at ₹6,000', (tester) async {
      final store = sampleLedger();
      final b = await pumpBudgetApp(tester, store: store);
      await b.open();
      await b.typeBudget(32000);
      expect(b.limitText('food'), '₹6,000');
      await b.tapSave();

      expect(b.state.budgetMinor, rupees(32000));
      expect(b.state.categories, seedCategories);
      expect(b.state.categories.first.limitMinor, rupees(6000));
      expect(await store.loadCategories(), seedCategories);

      await b.open();
      expect(b.limitText('food'), '₹6,000');
    });

    testWidgets('a limit is accepted from ₹1 to ₹99,99,999 only', (
      tester,
    ) async {
      final b = await pumpBudgetApp(tester);
      await b.open();

      await b.typeLimit('food', 0);
      expect(
        tester.widget<Text>(find.byKey(BudgetScreen.typedMessageKey)).data,
        BudgetScreen.belowMinimumMessage('Food limit'),
      );
      expect(b.app.haptics.count('refused'), 1);

      await b.app.type('1');
      await tester.tap(find.byKey(BudgetScreen.typedDoneKey));
      await tester.pump();
      expect(b.limitText('food'), '₹1');

      await b.startTyping(BudgetScreen.limitKey('food'), 99999999);
      expect(
        tester.widget<Text>(find.byKey(BudgetScreen.typedAmountKey)).data,
        '₹99,99,999',
      );
      await tester.tap(find.byKey(BudgetScreen.typedDoneKey));
      await tester.pump();
      expect(b.limitText('food'), '₹99,99,999');
    });

    testWidgets('Cancel on the pad keeps the limit as it was', (tester) async {
      final b = await pumpBudgetApp(tester);
      await b.open();

      await b.startTyping(BudgetScreen.limitKey('bills'), 500);
      await tester.tap(find.byKey(BudgetScreen.typedCancelKey));
      await tester.pump();

      expect(find.byType(BudgetScreen), findsOneWidget);
      expect(find.byType(NumberPad), findsNothing);
      expect(b.limitText('bills'), '₹11,000');
    });
  });

  group('saving', () {
    testWidgets('a failed save changes nothing and says so, with the screen '
        'still open and the edits intact', (tester) async {
      final inner = sampleLedger();
      final store = FailingLedgerStore(inner: inner);
      final b = await pumpBudgetApp(tester, store: store);
      final before = b.state;
      await b.open();
      await b.typeBudget(32000);
      await b.typeIncome(50000);
      await b.typeLimit('food', 8000);

      store.failOnSave = true;
      await b.tapSave();

      expect(store.failures, 1);
      expect(find.byType(BudgetScreen), findsOneWidget);
      expect(b.isOpen, isTrue);
      expect(
        tester.widget<Text>(find.byKey(BudgetScreen.messageKey)).data,
        BudgetScreen.saveFailedMessage,
      );
      expect(b.app.haptics.count('refused'), 1);
      expect(b.app.haptics.count('success'), 0);
      // The edits are still there to save again.
      expect(b.budgetText, '₹32,000');
      expect(b.rowAmount(BudgetScreen.incomeKey), '₹50,000');
      expect(b.limitText('food'), '₹8,000');
      // Nothing was saved and no figure moved.
      expect(b.state, same(before));
      expect(containerOf(tester).read(confirmationProvider), isNull);
      expect(await inner.budgetFor(const YearMonth(2026, 10)), rupees(30000));
      expect((await inner.loadProfile())!.monthlyIncomeMinor, rupees(45000));
      expect(await inner.loadCategories(), seedCategories);

      // Saving again once the store works saves all three.
      store.failOnSave = false;
      await b.tapSave();
      expect(find.byType(BudgetScreen), findsNothing);
      expect(find.text('left of ₹32,000'), findsOneWidget);
      expect(b.state.incomeMinor, rupees(50000));
      expect(b.state.categories.first.limitMinor, rupees(8000));
      expect(await inner.budgetFor(const YearMonth(2026, 10)), rupees(32000));
    });

    testWidgets('after a failed save, Cancel leaves home as it was', (
      tester,
    ) async {
      final store = FailingLedgerStore(inner: sampleLedger(), failOnSave: true);
      final b = await pumpBudgetApp(tester, store: store);
      final before = b.state;
      await b.open();
      await b.typeBudget(32000);
      await b.tapSave();
      await b.tapCancel();

      expect(find.byType(BudgetScreen), findsNothing);
      expect(b.state, same(before));
      expect(b.remainingText, '₹13,601');
      expect(find.text('left of ₹30,000'), findsOneWidget);
    });

    testWidgets('repeat taps on Save while a save is in flight are ignored', (
      tester,
    ) async {
      final store = GatedLedgerStore(inner: sampleLedger());
      final b = await pumpBudgetApp(tester, store: store);
      await b.open();
      await b.typeBudget(32000);

      store.hold();
      await tester.tap(find.byKey(BudgetScreen.saveKey));
      // Before a frame, and after one.
      await tester.tap(find.byKey(BudgetScreen.saveKey), warnIfMissed: false);
      await tester.pump();
      for (final key in [
        BudgetScreen.saveKey,
        BudgetScreen.saveKey,
        BudgetScreen.limitKey('food'),
        BudgetScreen.incomeKey,
      ]) {
        await tester.tap(find.byKey(key), warnIfMissed: false);
        await tester.pump();
      }
      expect(store.settingsSaves, 1);
      expect(find.byType(BudgetScreen), findsOneWidget);
      expect(find.byType(NumberPad), findsNothing);
      // Nothing changes until the save has finished.
      expect(b.state.budgetMinor, rupees(30000));

      store.release();
      await b.app.settle();
      expect(store.settingsSaves, 1);
      expect(find.byType(BudgetScreen), findsNothing);
      expect(b.state.budgetMinor, rupees(32000));
      expect(find.text('left of ₹32,000'), findsOneWidget);
    });

    testWidgets('if the screen was left before a save failed, the home '
        'screen says so', (tester) async {
      final store = GatedLedgerStore(inner: sampleLedger());
      final b = await pumpBudgetApp(tester, store: store);
      final before = b.state;
      await b.open();
      await b.typeBudget(32000);

      store.hold();
      await tester.tap(find.byKey(BudgetScreen.saveKey));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await b.app.settle();
      expect(find.byType(BudgetScreen), findsNothing);

      store.failOnSave = true;
      store.release();
      await b.app.settle();
      expect(find.text(BudgetScreen.saveFailedNotice), findsOneWidget);
      expect(b.state, same(before));
      expect(find.text('left of ₹30,000'), findsOneWidget);
    });

    testWidgets('Save with nothing changed closes without writing', (
      tester,
    ) async {
      final store = GatedLedgerStore(inner: sampleLedger());
      final b = await pumpBudgetApp(tester, store: store);
      final before = b.state;
      await b.open();
      await b.tapSave();

      expect(find.byType(BudgetScreen), findsNothing);
      expect(store.settingsSaves, 0);
      expect(b.state, same(before));
    });

    testWidgets('saved values survive rebuilding the app on the same store', (
      tester,
    ) async {
      final store = sampleLedger();
      final b = await pumpBudgetApp(tester, store: store);
      await b.open();
      await b.typeBudget(32000);
      await b.typeIncome(50000);
      await b.typeLimit('food', 8000);
      await b.tapSave();

      // The app is closed and started again on what the store holds.
      await tester.pumpWidget(const SizedBox());
      final again = await pumpBudgetApp(tester, store: store);

      expect(again.remainingText, '₹15,601');
      expect(find.text('left of ₹32,000'), findsOneWidget);
      expect(again.state.incomeMinor, rupees(50000));
      expect(again.state.budgetMinor, rupees(32000));
      expect(again.state.categories.first.limitMinor, rupees(8000));
      expect(again.state.categories.skip(1), seedCategories.skip(1));

      await again.open();
      expect(again.budgetText, '₹32,000');
      expect(find.text('of ₹50,000 income'), findsOneWidget);
      expect(again.rowAmount(BudgetScreen.incomeKey), '₹50,000');
      expect(again.limitText('food'), '₹8,000');
      expect(again.limitText('bills'), '₹11,000');
    });
  });

  group('fitting the screen', () {
    ScrollPosition scroll(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(BudgetScreen.scrollKey),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    double maxScroll(WidgetTester tester) => scroll(tester).maxScrollExtent;

    /// Walks the screen: as opened, scrolled to its end, with the vessel's
    /// pad open, and with the pad for a limit and for the income open.
    Future<void> expectNoOverflow(WidgetTester tester, Size size) async {
      final b = await pumpBudgetApp(tester, size: size, textScale: 1.5);
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      void check() {
        expect(tester.takeException(), isNull);
        for (final key in [BudgetScreen.cancelKey, BudgetScreen.saveKey]) {
          final r = tester.getRect(find.byKey(key));
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(size.width));
        }
      }

      await b.open();
      check();
      for (final c in seedCategories) {
        final r = tester.getRect(find.byKey(BudgetScreen.limitKey(c.id)));
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(size.width));
      }

      // Every limit and the note can be reached by scrolling.
      await b.typeLimit('food', 9999999);
      await tester.ensureVisible(find.byKey(BudgetScreen.overBudgetKey));
      await tester.pump();
      check();
      expect(
        tester.getRect(find.byKey(BudgetScreen.overBudgetKey)).bottom,
        lessThanOrEqualTo(size.height),
      );

      await tester.ensureVisible(find.byKey(BudgetVessel.budgetKey));
      await tester.pump();
      await tester.tap(find.byKey(BudgetVessel.budgetKey));
      await tester.pump();
      check();
      await tester.ensureVisible(find.byKey(BudgetVessel.typedCancelKey));
      await tester.pump();
      await tester.tap(find.byKey(BudgetVessel.typedCancelKey));
      await tester.pump();

      await b.startTyping(BudgetScreen.incomeKey, 9999999);
      expect(tester.takeException(), isNull);
      for (final key in [
        BudgetScreen.typedCancelKey,
        BudgetScreen.typedDoneKey,
        NumberPad.digitKey(1),
        NumberPad.deleteKey,
      ]) {
        final r = tester.getRect(find.byKey(key));
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(size.width));
      }
    }

    testWidgets('412x915: the pad for a limit fits without scrolling', (
      tester,
    ) async {
      final b = await pumpBudgetApp(tester);
      await b.open();
      expect(tester.takeException(), isNull);

      await b.startTyping(BudgetScreen.limitKey('food'), 8000);
      expect(tester.takeException(), isNull);
      expect(maxScroll(tester), 0);
      expect(
        tester.getRect(find.byKey(NumberPad.digitKey(0))).bottom,
        lessThanOrEqualTo(915),
      );
    });

    testWidgets('360x640: no overflow', (tester) async {
      final b = await pumpBudgetApp(tester, size: const Size(360, 640));
      await b.open();
      expect(tester.takeException(), isNull);
      await b.startTyping(BudgetScreen.limitKey('health'), 8000);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(BudgetScreen.typedDoneKey));
      await tester.pump();
      await tester.tap(find.byKey(BudgetVessel.budgetKey));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('text scale 1.5: no overflow at 412x915 or 360x640', (
      tester,
    ) async {
      await expectNoOverflow(tester, const Size(412, 915));
      await tester.pumpWidget(const SizedBox());
      await expectNoOverflow(tester, const Size(360, 640));
    });

    testWidgets('scrolled content stays between the system bars: nothing is '
        'drawn under the status bar', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 52, bottom: 48);
      addTearDown(tester.view.resetPadding);
      final b = await pumpBudgetApp(tester);
      await b.open();
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byKey(BudgetScreen.cancelKey)).top,
        greaterThanOrEqualTo(52),
      );

      final view = tester.getRect(find.byKey(BudgetScreen.scrollKey));
      expect(view.top, 52);
      expect(view.bottom, 915 - 48);
      expect(maxScroll(tester), greaterThan(0));
      scroll(tester).jumpTo(maxScroll(tester));
      await tester.pump();
      expect(
        tester.getRect(find.byKey(BudgetScreen.limitsTotalKey)).bottom,
        lessThanOrEqualTo(915 - 48),
      );
    });

    testWidgets('on a screen that has to scroll, dragging the vessel changes '
        'the budget and does not scroll the page', (tester) async {
      final b = await pumpBudgetApp(tester, size: const Size(360, 640));
      await b.open();
      expect(maxScroll(tester), greaterThan(0));

      final tank = tester.getRect(find.byKey(BudgetVessel.tankKey));
      await tester.dragFrom(tank.center, Offset(0, -tank.height));
      await tester.pump();

      expect(b.budgetText, '₹45,000');
      expect(scroll(tester).pixels, 0);
    });
  });
}
