import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tide/home/home_screen.dart';
import 'package:tide/main.dart';
import 'package:tide/state/clock.dart';
import 'package:tide/state/ledger.dart';
import 'package:tide/state/start_up.dart';
import 'package:tide/storage/storage.dart';
import 'package:tide/vessel/liquid_motion.dart';
import 'package:tide/vessel/liquid_painter.dart';
import 'package:tide/vessel/still_water.dart';
import 'package:tide/vessel/tilt.dart';
import 'package:tide/vessel/vessel_layer.dart';

/// 5 October 2026, mid-morning: the date the specs' figures are worked for.
final DateTime oct5 = DateTime(2026, 10, 5, 10);

/// A stand-in for the accelerometer that records whether it is being read.
class FakeTilt {
  FakeTilt() {
    _controller = StreamController<double>.broadcast(
      onListen: () => listens++,
      onCancel: () => cancels++,
    );
  }

  late final StreamController<double> _controller;

  /// How many times a subscription was opened and closed.
  int listens = 0;
  int cancels = 0;

  bool get isListening => _controller.hasListener;

  Stream<double> call() => _controller.stream;

  /// Sends a roll reading (sideways gravity divided by g).
  void add(double roll) => _controller.add(roll);

  void addError(Object error) => _controller.addError(error);
}

/// Pumps the whole app with the clock fixed, a [FakeTilt] in place of the
/// accelerometer and the fragment shader turned off, and returns the fake.
///
/// The app runs on [store], loaded as `main()` loads it. Left out, that is an
/// in-memory store holding the sample month for the clock's date (₹30,000
/// budget, twelve expenses), so the home screen shows. Pass
/// `MemoryLedgerStore()` for a ledger with no budget, which shows setup, or
/// a `FailingLedgerStore` to make writes fail.
///
/// The liquid's ticker never stops while the water is moving, so
/// `pumpAndSettle` would time out: pump explicit durations (see [pumpFor]),
/// or pass `still: true`, which turns on the platform's reduce-motion flag
/// and stops the ticker.
///
/// [clock], when given, replaces the fixed [now], so a test can move time on.
Future<FakeTilt> pumpHome(
  WidgetTester tester, {
  DateTime? now,
  Clock? clock,
  Size size = const Size(412, 915),
  double textScale = 1,
  bool still = false,
  WidgetBuilder? logFlowBuilder,
  LedgerStore? store,
  List<Override> overrides = const [],
}) async {
  _prepareView(tester, size: size, textScale: textScale, still: still);

  final tilt = FakeTilt();
  final fixed = now ?? oct5;
  final start = clock?.call() ?? fixed;
  final ledger = store ?? MemoryLedgerStore.sampleMonth(start);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...ledgerOverrides(ledger, await loadLedgerStart(ledger, start)),
        clockProvider.overrideWithValue(clock ?? () => fixed),
        tiltSourceProvider.overrideWithValue(tilt.call),
        liquidProgramLoaderProvider.overrideWithValue(noLiquidProgram),
        ...overrides,
      ],
      child: TideApp(
        home: TideRoot(home: HomeScreen(logFlowBuilder: logFlowBuilder)),
      ),
    ),
  );
  // One more frame: the liquid takes its level after the first layout.
  await tester.pump();
  return tilt;
}

void _prepareView(
  WidgetTester tester, {
  required Size size,
  required double textScale,
  required bool still,
}) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  tester.platformDispatcher
    ..textScaleFactorTestValue = textScale
    ..accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      disableAnimations: still,
    );
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

/// Pumps the app the way `main()` runs it: a [TideLauncher] given how
/// start-up ended ([initial]) and the start-up that Retry runs ([start]).
/// Exactly one frame is pumped, so a test can check what the first frame
/// shows. The clock, the accelerometer and the shader are replaced as in
/// [pumpHome]; [app] replaces the app that runs once the ledger is open.
Future<void> pumpLauncher(
  WidgetTester tester, {
  required StartResult initial,
  Future<StartResult> Function()? start,
  DateTime? now,
  Clock? clock,
  Size size = const Size(412, 915),
  bool still = false,
  Widget app = const TideApp(),
}) async {
  _prepareView(tester, size: size, textScale: 1, still: still);
  final tilt = FakeTilt();
  final fixed = now ?? oct5;
  await tester.pumpWidget(
    TideLauncher(
      initial: initial,
      start: start ?? () async => initial,
      overrides: [
        clockProvider.overrideWithValue(clock ?? () => fixed),
        tiltSourceProvider.overrideWithValue(tilt.call),
        liquidProgramLoaderProvider.overrideWithValue(noLiquidProgram),
      ],
      app: app,
    ),
  );
}

/// The provider container of the pumped app.
ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(TideRoot)));

/// The painter currently drawing the Vessel's canvas.
VesselPainter liquidPainter(WidgetTester tester) =>
    tester.widget<CustomPaint>(find.byKey(VesselLayer.liquidCanvasKey)).painter!
        as VesselPainter;

/// The liquid's motion state: height, target, lean, slosh, colour.
LiquidMotion liquidMotion(WidgetTester tester) => liquidPainter(tester).motion;

/// Pumps frames 16 ms apart for [duration], as a running app would.
Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  const frame = Duration(milliseconds: 16);
  for (var t = Duration.zero; t < duration; t += frame) {
    await tester.pump(frame);
  }
}
