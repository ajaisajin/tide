import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tide/budget/budget.dart';
import 'package:tide/home/confirmation_toast.dart';
import 'package:tide/home/home_screen.dart';
import 'package:tide/home/log_flow_state.dart';
import 'package:tide/home/pull_to_log.dart';
import 'package:tide/log/amount_ring.dart';
import 'package:tide/log/log_flow.dart';
import 'package:tide/log/number_pad.dart';
import 'package:tide/state/budget_state.dart';
import 'package:tide/state/haptics.dart';
import 'package:tide/state/ledger.dart';
import 'package:tide/storage/storage.dart';

import 'pump_home.dart';

/// Records haptic calls instead of making them.
class RecordingHaptics extends TideHaptics {
  final List<String> calls = [];

  int count(String name) => calls.where((c) => c == name).length;

  @override
  void tick() => calls.add('tick');

  @override
  void success() => calls.add('success');

  @override
  void refused() => calls.add('refused');
}

/// A clock a test can move forward.
class TestClock {
  TestClock([DateTime? start]) : now = start ?? oct5;

  DateTime now;

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
}

/// The app with the real log flow, a movable clock and recorded haptics.
class LogHarness {
  LogHarness(this.tester, this.clock, this.haptics);

  final WidgetTester tester;
  final TestClock clock;
  final RecordingHaptics haptics;

  BudgetNotifier get budget =>
      containerOf(tester).read(budgetProvider.notifier);
  List<Entry> get entries => containerOf(tester).read(budgetProvider).entries;
  BudgetSnapshot get snapshot =>
      containerOf(tester).read(budgetSnapshotProvider);
  bool get isOpen => containerOf(tester).read(logFlowOpenProvider);

  /// The ledger the app is running on.
  LedgerStore get store => containerOf(tester).read(ledgerStoreProvider);

  /// Lets the enter or exit animation finish.
  Future<void> settle() => pumpFor(tester, const Duration(milliseconds: 320));

  Future<void> open() async {
    if (find.byKey(ConfirmationToast.toastKey).evaluate().isEmpty) {
      await tester.tap(find.byKey(LogHandle.handleKey));
    } else {
      // The toast is over the handle: pull down instead.
      final size = tester.view.physicalSize;
      await tester.dragFrom(
        Offset(size.width / 2, size.height * 0.55),
        const Offset(0, 120),
      );
    }
    await settle();
    expect(find.byType(LogFlow), findsOneWidget);
  }

  Future<void> type(String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.byKey(NumberPad.digitKey(int.parse(d))));
      await tester.pump();
    }
  }

  Future<void> tapPebble(String categoryId) async {
    final pebble = find.byKey(LogFlow.pebbleKey(categoryId));
    await tester.ensureVisible(pebble);
    await tester.tap(pebble);
    await settle();
  }

  Future<void> tapSource(String source) async {
    final cell = find.byKey(LogFlow.sourceKey(source));
    await tester.ensureVisible(cell);
    await tester.tap(cell);
    await settle();
  }

  /// Opens the flow, types [digits] on the pad, waits [after] on the clock
  /// and files to [categoryId].
  Future<void> log(
    String digits,
    String categoryId, {
    Duration after = Duration.zero,
  }) async {
    await open();
    await type(digits);
    clock.advance(after);
    await tapPebble(categoryId);
  }

  Future<void> undo() async {
    await tester.tap(find.byKey(ConfirmationToast.undoKey));
    await settle();
  }

  String get amountText =>
      tester.widget<Text>(find.byKey(LogFlow.amountKey)).data!;

  /// Drags a finger round the ring by [radians] (negative is anticlockwise)
  /// at [speed] radians per second, starting at twelve o'clock.
  Future<void> turnRing(double radians, {required double speed}) async {
    final ring = find.byType(AmountRing);
    final centre = tester.getCenter(ring);
    final radius = tester.getSize(ring).shortestSide / 2 - 16;
    Offset at(double a) => centre + Offset(math.cos(a), math.sin(a)) * radius;
    const start = -math.pi / 2;
    const dt = 1 / 60;
    final perSample = speed.abs() * dt * radians.sign;
    final samples = (radians / perSample).round();
    var time = const Duration(seconds: 1);
    final gesture = await tester.createGesture();
    await gesture.down(at(start), timeStamp: time);
    for (var i = 1; i <= samples; i++) {
      time += const Duration(microseconds: 16667);
      await gesture.moveTo(at(start + perSample * i), timeStamp: time);
    }
    await gesture.up(timeStamp: time);
    await tester.pump();
  }
}

Widget _logFlow(BuildContext context) => const LogFlow();

/// Pumps the app with the real log flow in the overlay slot.
Future<LogHarness> pumpLogApp(
  WidgetTester tester, {
  Size size = const Size(412, 915),
  double textScale = 1,
  bool still = false,
  DateTime? start,
  LedgerStore? store,
  List<Override> overrides = const [],
}) async {
  final clock = TestClock(start);
  final haptics = RecordingHaptics();
  await pumpHome(
    tester,
    clock: clock.call,
    size: size,
    textScale: textScale,
    still: still,
    logFlowBuilder: _logFlow,
    store: store,
    overrides: [hapticsProvider.overrideWithValue(haptics), ...overrides],
  );
  expect(find.byType(HomeScreen), findsOneWidget);
  return LogHarness(tester, clock, haptics);
}
