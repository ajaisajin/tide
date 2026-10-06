import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide/budget/budget.dart';
import 'package:tide/log/number_pad.dart';
import 'package:tide/setup/budget_vessel.dart';
import 'package:tide/state/haptics.dart';
import 'package:tide/theme/tide_theme.dart';
import 'package:tide/vessel/liquid_motion.dart';
import 'package:tide/vessel/liquid_painter.dart';
import 'package:tide/vessel/still_water.dart';

/// Records haptic calls instead of making them.
class _RecordingHaptics extends TideHaptics {
  final List<String> calls = [];

  int count(String name) => calls.where((c) => c == name).length;

  @override
  void tick() => calls.add('tick');

  @override
  void success() => calls.add('success');

  @override
  void refused() => calls.add('refused');
}

/// A pumped [BudgetVessel] with the parent's side of it: the budget it was
/// last told, every report, and the recorded haptics.
class _Harness {
  _Harness(this.tester, this.haptics, this._budget);

  final WidgetTester tester;
  final _RecordingHaptics haptics;
  final ValueNotifier<int> _budget;

  /// Every budget reported through `onChanged`, in order.
  final List<int> reports = [];

  /// Every value reported through `onTypingChanged`, in order.
  final List<bool> typing = [];

  int get budgetMinor => _budget.value;

  String get budgetText =>
      tester.widget<Text>(find.byKey(BudgetVessel.budgetKey)).data!;

  String get setAsideText =>
      tester.widget<Text>(find.byKey(BudgetVessel.setAsideKey)).data!;

  Rect get tank => tester.getRect(find.byKey(BudgetVessel.tankKey));

  LiquidMotion get motion =>
      (tester
                  .widget<CustomPaint>(find.byKey(BudgetVessel.liquidCanvasKey))
                  .painter!
              as VesselPainter)
          .motion;

  /// The share of the tank the liquid is heading for, 0 to 1.
  double get targetLevel => motion.targetHeight / tank.height;

  /// A point in the tank at [level]: 0 is its bottom edge and 1 its top;
  /// more than 1 is above it.
  Offset at(double level) =>
      Offset(tank.center.dx, tank.bottom - tank.height * level);

  /// Drags from the level [from] to the level [to] and lets go.
  Future<void> drag({required double from, required double to}) async {
    final gesture = await tester.startGesture(at(from));
    await gesture.moveTo(at(to));
    await gesture.up();
    await tester.pump();
  }

  Future<void> openPad() async {
    await tester.tap(find.byKey(BudgetVessel.budgetKey));
    await tester.pump();
  }

  Future<void> type(String digits) async {
    for (final d in digits.split('')) {
      final key = find.byKey(NumberPad.digitKey(int.parse(d)));
      // On a very small screen with very large text the pad scrolls.
      await tester.ensureVisible(key);
      await tester.pump();
      await tester.tap(key);
    }
    await tester.pump();
  }

  Future<void> done() async {
    await tester.ensureVisible(find.byKey(BudgetVessel.typedDoneKey));
    await tester.pump();
    await tester.tap(find.byKey(BudgetVessel.typedDoneKey));
    await tester.pump();
  }
}

/// Pumps a [BudgetVessel] under a parent that keeps the budget, as the setup
/// and budget screens do, with the fragment shader turned off.
///
/// The liquid's ticker never stops while the water is moving, so
/// `pumpAndSettle` would time out: pump explicit durations.
Future<_Harness> _pumpVessel(
  WidgetTester tester, {
  required int income,
  int budget = 0,
  Size size = const Size(412, 915),
  bool still = false,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: still);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);

  final value = ValueNotifier<int>(rupees(budget));
  addTearDown(value.dispose);
  final harness = _Harness(tester, _RecordingHaptics(), value);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hapticsProvider.overrideWithValue(harness.haptics),
        liquidProgramLoaderProvider.overrideWithValue(noLiquidProgram),
      ],
      child: MaterialApp(
        theme: tideTheme(),
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ValueListenableBuilder<int>(
                valueListenable: value,
                builder: (context, budgetMinor, _) => BudgetVessel(
                  incomeMinor: rupees(income),
                  budgetMinor: budgetMinor,
                  onChanged: (next) {
                    harness.reports.add(next);
                    value.value = next;
                  },
                  onTypingChanged: harness.typing.add,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return harness;
}

void main() {
  group('dragging the level', () {
    testWidgets('a drag to two thirds with income ₹45,000 reads ₹30,000 and '
        '₹15,000 set aside', (tester) async {
      final vessel = await _pumpVessel(tester, income: 45000);
      expect(vessel.budgetText, '₹0');
      expect(vessel.setAsideText, '₹45,000 set aside');

      await vessel.drag(from: 0.1, to: 2 / 3);

      expect(vessel.budgetText, '₹30,000');
      expect(vessel.setAsideText, '₹15,000 set aside');
      expect(vessel.budgetMinor, rupees(30000));
      expect(vessel.targetLevel, closeTo(2 / 3, 1e-9));
    });

    testWidgets('the figures follow the finger while it is still down', (
      tester,
    ) async {
      final vessel = await _pumpVessel(tester, income: 45000);
      final gesture = await tester.startGesture(vessel.at(0.1));
      await gesture.moveTo(vessel.at(1 / 3));
      await tester.pump();
      expect(vessel.budgetText, '₹15,000');
      expect(vessel.setAsideText, '₹30,000 set aside');

      await gesture.moveTo(vessel.at(2 / 3));
      await tester.pump();
      expect(vessel.budgetText, '₹30,000');
      expect(vessel.setAsideText, '₹15,000 set aside');
      // The surface is under the finger, not springing after it.
      expect(vessel.motion.height, closeTo(vessel.tank.height * 2 / 3, 1e-6));
      await gesture.up();
    });

    testWidgets('dragging past the top stops at the income', (tester) async {
      final vessel = await _pumpVessel(tester, income: 45000);

      await vessel.drag(from: 0.5, to: 1.4);

      expect(vessel.budgetText, '₹45,000');
      expect(vessel.setAsideText, '₹0 set aside');
      expect(vessel.reports.last, rupees(45000));
      expect(vessel.reports.every((b) => b <= rupees(45000)), isTrue);
      expect(vessel.targetLevel, 1);
    });

    testWidgets('dragging past the bottom stops at ₹0', (tester) async {
      final vessel = await _pumpVessel(tester, income: 45000, budget: 30000);

      final gesture = await tester.startGesture(vessel.at(0.5));
      await gesture.moveTo(vessel.at(0.05));
      await gesture.moveBy(const Offset(0, 400));
      await gesture.up();
      await tester.pump();

      expect(vessel.budgetText, '₹0');
      expect(vessel.setAsideText, '₹45,000 set aside');
      expect(vessel.reports.every((b) => b >= 0), isTrue);
    });

    testWidgets('one haptic call fires per step', (tester) async {
      final vessel = await _pumpVessel(tester, income: 45000);
      double level(int budget) => budget / 45000;

      final gesture = await tester.startGesture(vessel.at(0.02));
      // Onto the ₹10,000 mark: twenty ₹500 steps from ₹0.
      await gesture.moveTo(vessel.at(level(10000)));
      await tester.pump();
      expect(vessel.budgetText, '₹10,000');
      expect(vessel.haptics.calls, List.filled(20, 'tick'));

      // One step at a time, up then down: one tick each.
      vessel.haptics.calls.clear();
      await gesture.moveTo(vessel.at(level(10500)));
      await tester.pump();
      expect(vessel.budgetText, '₹10,500');
      expect(vessel.haptics.calls, ['tick']);
      await gesture.moveTo(vessel.at(level(11000)));
      await tester.pump();
      expect(vessel.haptics.calls, ['tick', 'tick']);
      await gesture.moveTo(vessel.at(level(10500)));
      await tester.pump();
      expect(vessel.haptics.calls, ['tick', 'tick', 'tick']);

      // Moving within a step is silent.
      vessel.haptics.calls.clear();
      await gesture.moveBy(const Offset(0, -1));
      await gesture.moveBy(const Offset(0, 1));
      await tester.pump();
      expect(vessel.budgetText, '₹10,500');
      expect(vessel.haptics.calls, isEmpty);

      // Three steps in one move: three ticks.
      await gesture.moveTo(vessel.at(level(12000)));
      await gesture.up();
      await tester.pump();
      expect(vessel.budgetText, '₹12,000');
      expect(vessel.haptics.calls, List.filled(3, 'tick'));
      expect(vessel.haptics.count('tick'), 3);
    });

    testWidgets('an income below ₹10,000 moves in ₹100 steps', (tester) async {
      final vessel = await _pumpVessel(tester, income: 6000);

      final gesture = await tester.startGesture(vessel.at(0.02));
      await gesture.moveTo(vessel.at(2500 / 6000));
      await tester.pump();
      expect(vessel.budgetText, '₹2,500');
      vessel.haptics.calls.clear();
      await gesture.moveTo(vessel.at(2600 / 6000));
      await gesture.up();
      await tester.pump();

      expect(vessel.budgetText, '₹2,600');
      expect(vessel.setAsideText, '₹3,400 set aside');
      expect(vessel.haptics.calls, ['tick']);
    });

    testWidgets('a touch that does not travel changes nothing', (tester) async {
      final vessel = await _pumpVessel(tester, income: 45000, budget: 30000);
      await tester.tapAt(vessel.at(0.2));
      await tester.pump();
      expect(vessel.budgetText, '₹30,000');
      expect(vessel.reports, isEmpty);
      expect(vessel.haptics.calls, isEmpty);
    });

    testWidgets('a saved budget is shown at its share of the tank', (
      tester,
    ) async {
      final vessel = await _pumpVessel(tester, income: 45000, budget: 30000);
      expect(vessel.budgetText, '₹30,000');
      expect(vessel.setAsideText, '₹15,000 set aside');
      expect(vessel.motion.height, closeTo(vessel.tank.height * 2 / 3, 1e-6));
      expect(vessel.reports, isEmpty);
    });

    testWidgets('reduce motion paints still water at the same level', (
      tester,
    ) async {
      final vessel = await _pumpVessel(
        tester,
        income: 45000,
        budget: 30000,
        still: true,
      );
      final painter = tester
          .widget<CustomPaint>(find.byKey(BudgetVessel.liquidCanvasKey))
          .painter;
      expect(painter, isA<StillLiquidPainter>());
      expect(vessel.motion.height, closeTo(vessel.tank.height * 2 / 3, 1e-6));
      await tester.pumpAndSettle();
    });
  });

  group('typing the budget', () {
    testWidgets('tapping the budget opens the number pad', (tester) async {
      final vessel = await _pumpVessel(tester, income: 45000, budget: 30000);
      expect(find.byType(NumberPad), findsNothing);

      await vessel.openPad();

      expect(find.byType(NumberPad), findsOneWidget);
      expect(find.byKey(BudgetVessel.tankKey), findsNothing);
      expect(vessel.budgetText, '₹30,000');
      expect(vessel.typing, [true]);
      expect(vessel.reports, isEmpty);
    });

    testWidgets('₹28,750 is accepted and the level shows that share', (
      tester,
    ) async {
      final vessel = await _pumpVessel(tester, income: 45000, budget: 30000);
      await vessel.openPad();
      await vessel.type('28750');
      expect(vessel.budgetText, '₹28,750');
      expect(vessel.reports, isEmpty);

      await vessel.done();

      expect(find.byType(NumberPad), findsNothing);
      expect(vessel.reports, [rupees(28750)]);
      expect(vessel.typing, [true, false]);
      expect(vessel.budgetText, '₹28,750');
      expect(vessel.setAsideText, '₹16,250 set aside');
      expect(vessel.targetLevel, closeTo(28750 / 45000, 1e-9));
      expect(find.byKey(BudgetVessel.messageKey), findsNothing);

      // The liquid springs to the new level and comes to rest there.
      for (var i = 0; i < 250; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        vessel.motion.height / vessel.tank.height,
        closeTo(28750 / 45000, 0.002),
      );
    });

    testWidgets('₹50,000 against income ₹45,000 is refused with a message', (
      tester,
    ) async {
      final vessel = await _pumpVessel(tester, income: 45000, budget: 30000);
      await vessel.openPad();
      await vessel.type('50000');
      await vessel.done();

      expect(find.byType(NumberPad), findsOneWidget);
      expect(vessel.reports, isEmpty);
      expect(vessel.budgetMinor, rupees(30000));
      expect(
        tester.widget<Text>(find.byKey(BudgetVessel.messageKey)).data,
        'Budget cannot be more than your income of ₹45,000',
      );
      expect(vessel.haptics.calls, ['refused']);

      // Correcting the amount clears the message and is then accepted.
      await tester.tap(find.byKey(NumberPad.deleteKey));
      await tester.pump();
      expect(find.byKey(BudgetVessel.messageKey), findsNothing);
      expect(vessel.budgetText, '₹5,000');
      await vessel.done();
      expect(vessel.reports, [rupees(5000)]);
      expect(vessel.budgetText, '₹5,000');
    });

    testWidgets('the income itself is accepted and ₹0 is refused', (
      tester,
    ) async {
      final vessel = await _pumpVessel(tester, income: 45000, budget: 30000);
      await vessel.openPad();
      await vessel.type('0');
      await vessel.done();
      expect(
        tester.widget<Text>(find.byKey(BudgetVessel.messageKey)).data,
        'Budget must be at least ₹1',
      );
      expect(vessel.reports, isEmpty);

      await vessel.type('45000');
      await vessel.done();
      expect(vessel.reports, [rupees(45000)]);
      expect(vessel.targetLevel, 1);
    });

    testWidgets('Cancel closes the pad and changes nothing', (tester) async {
      final vessel = await _pumpVessel(tester, income: 45000, budget: 30000);
      await vessel.openPad();
      await vessel.type('1234');
      await tester.tap(find.byKey(BudgetVessel.typedCancelKey));
      await tester.pump();

      expect(find.byType(NumberPad), findsNothing);
      expect(vessel.budgetText, '₹30,000');
      expect(vessel.reports, isEmpty);
      expect(vessel.typing, [true, false]);
    });

    testWidgets('a budget above ₹9,99,999 can be typed', (tester) async {
      final vessel = await _pumpVessel(tester, income: 2500000);
      await vessel.openPad();
      await vessel.type('1250000');
      // An eighth digit would pass ₹99,99,999 and is ignored.
      await vessel.type('9');
      expect(vessel.budgetText, '₹12,50,000');
      await vessel.done();
      expect(vessel.reports, [rupees(1250000)]);
    });

    testWidgets('dragging from a typed budget ticks once for each stop', (
      tester,
    ) async {
      final vessel = await _pumpVessel(tester, income: 45000, budget: 28750);
      final gesture = await tester.startGesture(vessel.at(0.5));
      // ₹28,750 to ₹30,000 passes ₹29,000, ₹29,500 and ₹30,000.
      await gesture.moveTo(vessel.at(2 / 3));
      await gesture.up();
      await tester.pump();
      expect(vessel.budgetText, '₹30,000');
      expect(vessel.haptics.calls, List.filled(3, 'tick'));
    });

    testWidgets('the pad fits a small screen with large text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      final vessel = await _pumpVessel(
        tester,
        income: 45000,
        budget: 30000,
        size: const Size(320, 568),
      );
      expect(tester.takeException(), isNull);
      await vessel.openPad();
      await vessel.type('50000');
      await vessel.done();
      expect(find.byKey(BudgetVessel.messageKey), findsOneWidget);
      expect(tester.takeException(), isNull);

      await vessel.type('28750');
      await vessel.done();
      expect(vessel.reports, [rupees(28750)]);
      expect(tester.takeException(), isNull);
    });
  });

  group('semantics', () {
    SemanticsNode node(WidgetTester tester) =>
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Budget vessel')));

    void perform(WidgetTester tester, SemanticsAction action) {
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: action,
          nodeId: node(tester).id,
          viewId: tester.view.viewId,
        ),
      );
    }

    testWidgets('the vessel is an adjustable value that says the budget', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpVessel(tester, income: 45000, budget: 30000);

      final data = node(tester).getSemanticsData();
      expect(
        data.label,
        'Budget vessel, ₹30,000 of ₹45,000 income, ₹15,000 set aside',
      );
      expect(data.hasAction(SemanticsAction.increase), isTrue);
      expect(data.hasAction(SemanticsAction.decrease), isTrue);
      // The figures are said once, by the vessel.
      expect(find.semantics.byLabel(RegExp('30,000')), findsOne);
      expect(find.bySemanticsLabel('Type the budget'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the increase action raises the budget by one step and the '
        'label carries the new amount', (tester) async {
      final handle = tester.ensureSemantics();
      final vessel = await _pumpVessel(tester, income: 45000, budget: 30000);

      perform(tester, SemanticsAction.increase);
      await tester.pump();

      expect(vessel.reports, [rupees(30500)]);
      expect(vessel.budgetText, '₹30,500');
      expect(
        node(tester).label,
        'Budget vessel, ₹30,500 of ₹45,000 income, ₹14,500 set aside',
      );
      expect(vessel.haptics.calls, ['tick']);
      expect(vessel.targetLevel, closeTo(30500 / 45000, 1e-9));
      handle.dispose();
    });

    testWidgets('the decrease action lowers the budget by one step', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final vessel = await _pumpVessel(tester, income: 45000, budget: 30000);

      perform(tester, SemanticsAction.decrease);
      await tester.pump();

      expect(vessel.reports, [rupees(29500)]);
      expect(node(tester).label, contains('₹29,500'));
      expect(vessel.haptics.calls, ['tick']);
      handle.dispose();
    });

    testWidgets('a small income steps by ₹100', (tester) async {
      final handle = tester.ensureSemantics();
      final vessel = await _pumpVessel(tester, income: 6000, budget: 2500);
      perform(tester, SemanticsAction.increase);
      await tester.pump();
      expect(vessel.reports, [rupees(2600)]);
      expect(node(tester).label, contains('₹2,600'));
      handle.dispose();
    });

    testWidgets('a full vessel offers no increase and an empty one no '
        'decrease', (tester) async {
      final handle = tester.ensureSemantics();
      final vessel = await _pumpVessel(tester, income: 45000, budget: 45000);
      var data = node(tester).getSemanticsData();
      expect(data.hasAction(SemanticsAction.increase), isFalse);
      expect(data.hasAction(SemanticsAction.decrease), isTrue);

      await vessel.drag(from: 0.5, to: -0.2);
      data = node(tester).getSemanticsData();
      expect(data.label, contains('₹0 of ₹45,000'));
      expect(data.hasAction(SemanticsAction.increase), isTrue);
      expect(data.hasAction(SemanticsAction.decrease), isFalse);
      handle.dispose();
    });

    testWidgets('the typing button opens the pad, and a refusal is a live '
        'region', (tester) async {
      final handle = tester.ensureSemantics();
      final vessel = await _pumpVessel(tester, income: 45000, budget: 30000);

      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.tap,
          nodeId: tester
              .getSemantics(find.bySemanticsLabel('Type the budget'))
              .id,
          viewId: tester.view.viewId,
        ),
      );
      await tester.pump();
      expect(find.byType(NumberPad), findsOneWidget);

      await vessel.type('50000');
      await vessel.done();
      final message = tester.getSemantics(
        find.bySemanticsLabel(RegExp('cannot be more than your income')),
      );
      expect(message.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });
  });
}
