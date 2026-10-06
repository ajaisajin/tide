import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tide/budget/budget.dart';
import 'package:tide/home/home_screen.dart';
import 'package:tide/log/number_pad.dart';
import 'package:tide/setup/budget_vessel.dart';
import 'package:tide/setup/setup_screen.dart';
import 'package:tide/state/budget_state.dart';
import 'package:tide/state/haptics.dart';
import 'package:tide/state/ledger.dart';
import 'package:tide/storage/storage.dart';
import 'package:tide/vessel/vessel_layer.dart';

import '../support/failing_ledger_store.dart';
import '../support/log_helpers.dart' show RecordingHaptics;
import '../support/pump_home.dart';

const _october = YearMonth(2026, 10);

/// A budget notifier whose `completeSetup` can be held back, so a test can
/// look at the setup screen while the save is in flight.
class _GatedBudget extends BudgetNotifier {
  Completer<void>? _gate;

  /// How many times setup has been asked to complete, held or not.
  int completions = 0;

  void hold() => _gate ??= Completer<void>();

  void release() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<void> completeSetup({
    required int incomeMinor,
    required int budgetMinor,
  }) async {
    completions++;
    await _gate?.future;
    return super.completeSetup(
      incomeMinor: incomeMinor,
      budgetMinor: budgetMinor,
    );
  }
}

/// The app on a ledger with no budget, which opens on setup.
class _Setup {
  _Setup(this.tester, this.haptics);

  final WidgetTester tester;
  final RecordingHaptics haptics;

  /// The ledger the app is running on.
  LedgerStore get store => containerOf(tester).read(ledgerStoreProvider);

  BudgetState get state => containerOf(tester).read(budgetProvider);

  String get incomeText =>
      tester.widget<Text>(find.byKey(SetupScreen.incomeKey)).data!;

  String get budgetText =>
      tester.widget<Text>(find.byKey(BudgetVessel.budgetKey)).data!;

  String get setAsideText =>
      tester.widget<Text>(find.byKey(BudgetVessel.setAsideKey)).data!;

  String get message =>
      tester.widget<Text>(find.byKey(SetupScreen.messageKey)).data!;

  /// Whether Next or Confirm, whichever [key] is, answers a tap.
  bool enabled(Key key) =>
      tester
          .widget<InkWell>(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(InkWell),
            ),
          )
          .onTap !=
      null;

  Future<void> type(String digits) async {
    for (final d in digits.split('')) {
      final key = find.byKey(NumberPad.digitKey(int.parse(d)));
      // On a small screen with large text the pad scrolls.
      await tester.ensureVisible(key);
      await tester.pump();
      await tester.tap(key);
    }
    await tester.pump();
  }

  Future<void> tap(Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pump();
    await tester.tap(find.byKey(key));
    await tester.pump();
  }

  /// Types [digits] as the income and presses Next.
  Future<void> enterIncome(String digits) async {
    await type(digits);
    await tap(SetupScreen.incomeNextKey);
  }

  /// Drags the water from near the bottom of the tank to [level], where 0 is
  /// its bottom edge and 1 its top.
  Future<void> dragTo(double level) async {
    final tank = tester.getRect(find.byKey(BudgetVessel.tankKey));
    Offset at(double l) =>
        Offset(tank.center.dx, tank.bottom - tank.height * l);
    final gesture = await tester.startGesture(at(level > 0.3 ? 0.05 : 0.95));
    await gesture.moveTo(at(level));
    await gesture.up();
    await tester.pump();
  }

  /// Types [digits] as the budget on the vessel's own pad and presses Done.
  Future<void> typeBudget(String digits) async {
    await tap(BudgetVessel.budgetKey);
    await type(digits);
    await tap(BudgetVessel.typedDoneKey);
  }

  /// Types [digits] on the vessel's pad, already open, and presses Done.
  Future<void> typeBudgetDigits(String digits) async {
    await type(digits);
    await tap(BudgetVessel.typedDoneKey);
  }

  Future<void> confirm() async {
    await tap(SetupScreen.confirmKey);
    // The save answers, then the root widget rebuilds.
    await tester.pump();
    await tester.pump();
  }
}

Future<_Setup> _pumpSetup(
  WidgetTester tester, {
  LedgerStore? store,
  Size size = const Size(412, 915),
  double textScale = 1,
  List<Override> overrides = const [],
}) async {
  final haptics = RecordingHaptics();
  await pumpHome(
    tester,
    store: store ?? MemoryLedgerStore(),
    size: size,
    textScale: textScale,
    overrides: [hapticsProvider.overrideWithValue(haptics), ...overrides],
  );
  expect(find.byType(SetupScreen), findsOneWidget);
  return _Setup(tester, haptics);
}

void main() {
  group('monthly income', () {
    testWidgets('setup opens on the income pad at ₹0, with no vessel and '
        'nothing to confirm yet', (tester) async {
      final setup = await _pumpSetup(tester);

      expect(setup.incomeText, '₹0');
      expect(find.byType(NumberPad), findsOneWidget);
      expect(find.byType(BudgetVessel), findsNothing);
      expect(find.byKey(SetupScreen.confirmKey), findsNothing);
      expect(setup.enabled(SetupScreen.incomeNextKey), isFalse);

      // Next does nothing without an income.
      await setup.tap(SetupScreen.incomeNextKey);
      expect(find.byType(BudgetVessel), findsNothing);
    });

    testWidgets('income entered: ₹45,000 is shown as income and the vessel '
        'is offered to set the budget', (tester) async {
      final setup = await _pumpSetup(tester);

      await setup.type('45000');
      expect(setup.incomeText, '₹45,000');
      expect(setup.enabled(SetupScreen.incomeNextKey), isTrue);
      await setup.tap(SetupScreen.incomeNextKey);

      expect(setup.incomeText, '₹45,000');
      final vessel = tester.widget<BudgetVessel>(find.byType(BudgetVessel));
      expect(vessel.incomeMinor, rupees(45000));
      expect(vessel.budgetMinor, 0);
      expect(setup.budgetText, '₹0');
      expect(setup.setAsideText, '₹45,000 set aside');
      expect(find.byKey(SetupScreen.confirmKey), findsOneWidget);
    });

    testWidgets('the pad takes up to ₹99,99,999 and ignores a digit that '
        'would pass it', (tester) async {
      final setup = await _pumpSetup(tester);

      await setup.type('99999999');
      expect(setup.incomeText, '₹99,99,999');
      await setup.tap(SetupScreen.incomeNextKey);
      expect(
        tester.widget<BudgetVessel>(find.byType(BudgetVessel)).incomeMinor,
        maxAmountMinor,
      );
    });

    testWidgets('delete drops the last digit, and an income deleted to ₹0 '
        'cannot go on', (tester) async {
      final setup = await _pumpSetup(tester);

      await setup.type('45');
      await setup.tap(NumberPad.deleteKey);
      expect(setup.incomeText, '₹4');
      expect(setup.enabled(SetupScreen.incomeNextKey), isTrue);
      await setup.tap(NumberPad.deleteKey);
      expect(setup.incomeText, '₹0');
      expect(setup.enabled(SetupScreen.incomeNextKey), isFalse);
    });

    testWidgets('the income can be changed before confirming, and the '
        'budget chosen so far is kept', (tester) async {
      final setup = await _pumpSetup(tester);
      await setup.enterIncome('45000');
      await setup.dragTo(2 / 3);
      expect(setup.budgetText, '₹30,000');

      await setup.tap(SetupScreen.changeIncomeKey);
      expect(find.byType(BudgetVessel), findsNothing);
      expect(find.byType(NumberPad), findsOneWidget);
      expect(setup.incomeText, '₹45,000');

      // The first digit starts a new amount.
      await setup.enterIncome('60000');
      expect(setup.incomeText, '₹60,000');
      expect(setup.budgetText, '₹30,000');
      expect(setup.setAsideText, '₹30,000 set aside');
    });

    testWidgets('an income changed to less than the budget brings the '
        'budget down to it', (tester) async {
      final setup = await _pumpSetup(tester);
      await setup.enterIncome('45000');
      await setup.dragTo(2 / 3);

      await setup.tap(SetupScreen.changeIncomeKey);
      await setup.enterIncome('20000');

      expect(setup.incomeText, '₹20,000');
      expect(setup.budgetText, '₹20,000');
      expect(setup.setAsideText, '₹0 set aside');
      expect(setup.enabled(SetupScreen.confirmKey), isTrue);
    });
  });

  group('choosing the budget', () {
    testWidgets('no budget yet: a budget of ₹0 cannot be confirmed', (
      tester,
    ) async {
      final setup = await _pumpSetup(tester);
      await setup.enterIncome('45000');

      expect(setup.budgetText, '₹0');
      expect(setup.enabled(SetupScreen.confirmKey), isFalse);
      expect(setup.message, SetupScreen.noBudgetMessage);

      await setup.confirm();
      expect(find.byType(SetupScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(setup.state.setupComplete, isFalse);
      expect(await setup.store.hasAnyBudget(), isFalse);
      expect(await setup.store.loadProfile(), isNull);

      // Dragged up and back down to ₹0, it still cannot.
      await setup.dragTo(2 / 3);
      expect(setup.enabled(SetupScreen.confirmKey), isTrue);
      await setup.dragTo(-0.2);
      expect(setup.budgetText, '₹0');
      expect(setup.enabled(SetupScreen.confirmKey), isFalse);
    });

    testWidgets('dragging the level to two thirds reads ₹30,000 with '
        '₹15,000 set aside, and Confirm answers', (tester) async {
      final setup = await _pumpSetup(tester);
      await setup.enterIncome('45000');
      await setup.dragTo(2 / 3);

      expect(setup.budgetText, '₹30,000');
      expect(setup.setAsideText, '₹15,000 set aside');
      expect(setup.enabled(SetupScreen.confirmKey), isTrue);
      expect(setup.message, SetupScreen.readyMessage);
    });

    testWidgets('a typed budget is taken on Done, and Confirm waits while '
        'the pad is open', (tester) async {
      final setup = await _pumpSetup(tester);
      await setup.enterIncome('45000');
      await setup.dragTo(2 / 3);

      await setup.tap(BudgetVessel.budgetKey);
      await setup.type('28750');
      expect(setup.enabled(SetupScreen.confirmKey), isFalse);
      await setup.confirm();
      expect(find.byType(SetupScreen), findsOneWidget);
      expect(await setup.store.hasAnyBudget(), isFalse);

      await setup.tap(BudgetVessel.typedDoneKey);
      expect(setup.budgetText, '₹28,750');
      expect(setup.enabled(SetupScreen.confirmKey), isTrue);
    });

    testWidgets('a typed budget above the income is refused and does not '
        'become the budget', (tester) async {
      final setup = await _pumpSetup(tester);
      await setup.enterIncome('45000');
      await setup.typeBudget('50000');

      expect(
        tester.widget<Text>(find.byKey(BudgetVessel.messageKey)).data,
        contains('cannot be more than your income'),
      );
      expect(setup.enabled(SetupScreen.confirmKey), isFalse);
      await setup.tap(BudgetVessel.typedCancelKey);
      expect(setup.budgetText, '₹0');
      expect(setup.enabled(SetupScreen.confirmKey), isFalse);
    });

    testWidgets('going back to the income with the budget pad open does '
        'not leave Confirm waiting', (tester) async {
      final setup = await _pumpSetup(tester);
      await setup.enterIncome('45000');
      await setup.dragTo(2 / 3);
      await setup.tap(BudgetVessel.budgetKey);
      await setup.type('100');

      await setup.tap(SetupScreen.changeIncomeKey);
      await setup.tap(SetupScreen.incomeNextKey);

      expect(setup.budgetText, '₹30,000');
      expect(setup.enabled(SetupScreen.confirmKey), isTrue);
    });
  });

  group('nothing is saved before Confirm', () {
    testWidgets('entering, changing and typing write nothing to the store', (
      tester,
    ) async {
      // Every write would fail and be counted.
      final store = FailingLedgerStore(failOnSave: true, failOnInsert: true);
      final setup = await _pumpSetup(tester, store: store);

      await setup.enterIncome('45000');
      await setup.dragTo(2 / 3);
      await setup.typeBudget('28750');
      await setup.tap(SetupScreen.changeIncomeKey);
      await setup.enterIncome('60000');
      await setup.dragTo(0.5);
      await pumpFor(tester, const Duration(milliseconds: 300));

      expect(store.failures, 0);
      expect(await store.loadProfile(), isNull);
      expect(await store.hasAnyBudget(), isFalse);
      expect(await store.budgetFor(_october), isNull);
      expect(await store.loadCategories(), isEmpty);
      expect(setup.state.setupComplete, isFalse);
      expect(setup.state.incomeMinor, isNull);
      expect(setup.state.budgetMinor, 0);
      expect(find.byType(SetupScreen), findsOneWidget);
    });
  });

  group('completing setup', () {
    testWidgets('confirming income ₹45,000 and budget ₹30,000 shows home '
        'with ₹30,000 remaining, "left of ₹30,000", "100% full", every '
        'category at ₹0 and the default limits, and the store holds the '
        'income, the month\'s budget and the limits', (tester) async {
      final setup = await _pumpSetup(tester);
      await setup.enterIncome('45000');
      await setup.dragTo(2 / 3);
      expect(setup.budgetText, '₹30,000');

      await setup.confirm();

      expect(find.byType(SetupScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(VesselLayer.remainingKey)).data,
        '₹30,000',
      );
      expect(find.text('left of ₹30,000'), findsOneWidget);
      expect(find.text('100% full'), findsOneWidget);
      // One ₹0 for each pebble.
      expect(find.text('₹0'), findsNWidgets(6));

      const limits = {
        'Food': 6000,
        'Bills': 10500,
        'Travel': 3000,
        'Shopping': 2100,
        'Fun': 1500,
        'Health': 1500,
      };
      final snapshot = containerOf(tester).read(budgetSnapshotProvider);
      expect(snapshot.remainingMinor, rupees(30000));
      expect(snapshot.availableMinor, rupees(30000));
      expect({
        for (final c in snapshot.categories) c.category.name: c.spentMinor,
      }, limits.map((name, _) => MapEntry(name, 0)));
      expect({
        for (final c in snapshot.categories) c.category.name: c.limitMinor,
      }, limits.map((name, limit) => MapEntry(name, rupees(limit))));
      expect(setup.state.incomeMinor, rupees(45000));
      expect(setup.haptics.count('success'), 1);

      // The store holds all three.
      final store = setup.store;
      expect((await store.loadProfile())!.monthlyIncomeMinor, rupees(45000));
      expect(await store.budgetFor(_october), rupees(30000));
      expect(await store.hasAnyBudget(), isTrue);
      expect({
        for (final c in await store.loadCategories()) c.name: c.limitMinor,
      }, limits.map((name, limit) => MapEntry(name, rupees(limit))));
      // Income is a reference figure, not an entry.
      expect(await store.entriesForMonth(_october), isEmpty);
    });

    testWidgets('a typed budget is what is saved', (tester) async {
      final setup = await _pumpSetup(tester);
      await setup.enterIncome('45000');
      await setup.typeBudget('18400');
      await setup.confirm();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('left of ₹18,400'), findsOneWidget);
      expect(await setup.store.budgetFor(_october), rupees(18400));
      final limits = {
        for (final c in await setup.store.loadCategories()) c.id: c.limitMinor,
      };
      expect(limits['food'], rupees(3600));
      expect(limits['shop'], rupees(1200));
    });

    testWidgets('a save that fails stays on setup with what was entered and '
        'says it could not be saved; Confirm then works once the store '
        'does', (tester) async {
      final store = FailingLedgerStore();
      final setup = await _pumpSetup(tester, store: store);
      await setup.enterIncome('45000');
      await setup.dragTo(2 / 3);

      store.failOnSave = true;
      await setup.confirm();

      expect(store.failures, greaterThan(0));
      expect(find.byType(SetupScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(setup.incomeText, '₹45,000');
      expect(setup.budgetText, '₹30,000');
      expect(setup.message, SetupScreen.saveFailedMessage);
      expect(setup.message, contains('could not be saved'));
      expect(setup.state.setupComplete, isFalse);
      expect(await store.hasAnyBudget(), isFalse);
      expect(setup.haptics.count('success'), 0);
      expect(setup.haptics.count('refused'), 1);

      // Nothing is stuck: the vessel still moves, and that clears the
      // message.
      await setup.dragTo(0.5);
      expect(setup.budgetText, '₹22,500');
      expect(setup.message, SetupScreen.readyMessage);
      await setup.dragTo(2 / 3);

      store.failOnSave = false;
      await setup.confirm();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('left of ₹30,000'), findsOneWidget);
      expect((await store.loadProfile())!.monthlyIncomeMinor, rupees(45000));
      expect(await store.budgetFor(_october), rupees(30000));
    });

    testWidgets('taps on Confirm are ignored while a save is in flight', (
      tester,
    ) async {
      final budget = _GatedBudget();
      final setup = await _pumpSetup(
        tester,
        overrides: [budgetProvider.overrideWith(() => budget)],
      );
      await setup.enterIncome('45000');
      await setup.dragTo(2 / 3);

      budget.hold();
      final confirm = find.byKey(SetupScreen.confirmKey);
      await tester.tap(confirm);
      // Before a frame, and after one.
      await tester.tap(confirm, warnIfMissed: false);
      await tester.pump();
      await tester.tap(confirm, warnIfMissed: false);
      await tester.pump();
      expect(budget.completions, 1);
      expect(find.byType(SetupScreen), findsOneWidget);
      expect(setup.state.setupComplete, isFalse);

      // Neither the vessel nor the income can be changed under the save.
      await setup.dragTo(0.2);
      expect(setup.budgetText, '₹30,000');
      await tester.tap(
        find.byKey(SetupScreen.changeIncomeKey),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(find.byType(BudgetVessel), findsOneWidget);

      budget.release();
      await tester.pump();
      await tester.pump();
      expect(budget.completions, 1);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('left of ₹30,000'), findsOneWidget);
      expect(await setup.store.budgetFor(_october), rupees(30000));
    });

    testWidgets('a save that fails after being held can be tried again', (
      tester,
    ) async {
      final budget = _GatedBudget();
      final store = FailingLedgerStore();
      final setup = await _pumpSetup(
        tester,
        store: store,
        overrides: [budgetProvider.overrideWith(() => budget)],
      );
      await setup.enterIncome('45000');
      await setup.dragTo(2 / 3);

      budget.hold();
      store.failOnSave = true;
      await setup.tap(SetupScreen.confirmKey);
      budget.release();
      await tester.pump();
      await tester.pump();
      expect(setup.message, SetupScreen.saveFailedMessage);

      store.failOnSave = false;
      await setup.confirm();
      expect(budget.completions, 2);
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });

  group('fitting the screen', () {
    ScrollPosition scroll(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(SetupScreen.scrollKey),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;

    double maxScroll(WidgetTester tester) => scroll(tester).maxScrollExtent;

    void expectInside(WidgetTester tester, Key key, Size size) {
      final r = tester.getRect(find.byKey(key));
      expect(r.left, greaterThanOrEqualTo(0), reason: '$key');
      expect(r.right, lessThanOrEqualTo(size.width), reason: '$key');
    }

    /// Walks through both steps, the vessel's pad and the failure message,
    /// checking for overflow at each.
    Future<void> walk(WidgetTester tester, _Setup setup, Size size) async {
      expect(tester.takeException(), isNull);
      expectInside(tester, SetupScreen.incomeKey, size);
      expectInside(tester, SetupScreen.incomeNextKey, size);
      for (var d = 0; d <= 9; d++) {
        expectInside(tester, NumberPad.digitKey(d), size);
      }

      // The widest income there can be.
      await setup.enterIncome('9999999');
      expect(tester.takeException(), isNull);
      expectInside(tester, SetupScreen.changeIncomeKey, size);
      expectInside(tester, SetupScreen.incomeKey, size);
      expectInside(tester, BudgetVessel.tankKey, size);
      expectInside(tester, SetupScreen.confirmKey, size);
      // The test font is about twice as wide as the app's, so the figures
      // wrap onto more lines here than on a phone.
      expect(
        tester.getSize(find.byKey(BudgetVessel.tankKey)).height,
        greaterThanOrEqualTo(30),
      );

      await setup.dragTo(1.2);
      expect(setup.budgetText, '₹99,99,999');
      expect(tester.takeException(), isNull);

      await setup.tap(BudgetVessel.budgetKey);
      await setup.type('99999999');
      expect(tester.takeException(), isNull);
      await setup.tap(BudgetVessel.typedDoneKey);
      expect(tester.takeException(), isNull);
    }

    testWidgets('412x915 with system bars: both steps fit without scrolling', (
      tester,
    ) async {
      tester.view.padding = const FakeViewPadding(top: 49, bottom: 48);
      const size = Size(412, 915);
      final setup = await _pumpSetup(tester, size: size);
      expect(maxScroll(tester), 0);
      expect(
        tester.getRect(find.byKey(SetupScreen.incomeNextKey)).bottom,
        lessThanOrEqualTo(915 - 48),
      );
      await walk(tester, setup, size);
      expect(maxScroll(tester), 0);
      expect(
        tester.getRect(find.byKey(SetupScreen.confirmKey)).bottom,
        lessThanOrEqualTo(915 - 48),
      );
      expect(
        tester.getRect(find.byKey(SetupScreen.changeIncomeKey)).top,
        greaterThanOrEqualTo(49),
      );
    });

    testWidgets('360x640: no overflow on either step, and both fit without '
        'scrolling', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      const size = Size(360, 640);
      final setup = await _pumpSetup(tester, size: size);
      expect(maxScroll(tester), 0);
      await walk(tester, setup, size);
      expect(maxScroll(tester), 0);
    });

    testWidgets('360x640: with the budget pad open the page scrolls and '
        'the whole pad is laid out, not cut short inside the vessel', (
      tester,
    ) async {
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
      final setup = await _pumpSetup(tester, size: const Size(360, 640));
      await setup.enterIncome('45000');
      await setup.tap(BudgetVessel.budgetKey);
      expect(tester.takeException(), isNull);

      // The vessel's own scroll view has nothing to scroll: every key is
      // reached by scrolling the page.
      final inner = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(BudgetVessel),
          matching: find.byType(Scrollable),
        ),
      );
      expect(inner.position.maxScrollExtent, 0);
      final vessel = tester.getRect(find.byType(BudgetVessel));
      for (var d = 0; d <= 9; d++) {
        final key = tester.getRect(find.byKey(NumberPad.digitKey(d)));
        expect(key.bottom, lessThanOrEqualTo(vessel.bottom), reason: '$d');
      }

      await setup.typeBudgetDigits('28750');
      expect(setup.budgetText, '₹28,750');
      expect(maxScroll(tester), 0);
    });

    testWidgets('text scale 1.5: no overflow at 412x915 or 360x640', (
      tester,
    ) async {
      for (final size in const [Size(412, 915), Size(360, 640)]) {
        tester.view.padding = const FakeViewPadding(top: 49, bottom: 48);
        final store = FailingLedgerStore(failOnSave: true);
        final setup = await _pumpSetup(
          tester,
          store: store,
          size: size,
          textScale: 1.5,
        );
        await walk(tester, setup, size);

        // The failure message is the longest line above Confirm.
        await setup.confirm();
        expect(setup.message, SetupScreen.saveFailedMessage);
        expect(tester.takeException(), isNull);
        expectInside(tester, SetupScreen.messageKey, size);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('on a screen that has to scroll, dragging the level does '
        'not scroll the page and Confirm still works', (tester) async {
      final setup = await _pumpSetup(
        tester,
        size: const Size(360, 480),
        textScale: 1.5,
      );
      expect(tester.takeException(), isNull);
      await setup.enterIncome('45000');
      expect(tester.takeException(), isNull);
      expect(maxScroll(tester), greaterThan(0));

      await tester.ensureVisible(find.byKey(BudgetVessel.tankKey));
      await tester.pump();
      final before = scroll(tester).pixels;
      await setup.dragTo(2 / 3);
      expect(setup.budgetText, '₹30,000');
      expect(scroll(tester).pixels, before);

      await setup.confirm();
      expect(tester.takeException(), isNull);
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });
}
