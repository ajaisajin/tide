import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../budget/budget.dart';
import '../home/log_flow_state.dart';
import '../state/budget_state.dart';
import '../theme/tide_theme.dart';
import 'frame_monitor.dart';
import 'liquid_motion.dart';
import 'liquid_painter.dart';
import 'pebble.dart';
import 'still_water.dart';
import 'tilt.dart';
import 'vessel_geometry.dart';

/// The spoken summary of the Vessel: month and mood, then the percentage
/// left, the amount remaining and the safe-to-spend figure.
String vesselSemanticSummary(BudgetSnapshot s) {
  final overspent = s.isOverspent
      ? ', overspent by ${formatRupees(-s.remainingMinor)}'
      : '';
  return '${monthName(s.now.month)}, ${s.moodLabel}. '
      'Budget ${s.fillPercent}% left, '
      '${formatRupees(s.remainingMinor)} remaining '
      'of ${formatRupees(s.availableMinor)}$overspent, '
      'safe today ${formatRupees(s.safeToSpendTodayMinor)}';
}

/// The Vessel: the liquid canvas with the month's figures and the category
/// pebbles laid over it.
///
/// The liquid is painted from a [LiquidMotion] that a ticker advances, so it
/// moves without this widget rebuilding. This widget rebuilds only when the
/// budget snapshot, the still-water flag or the layout changes.
class VesselLayer extends ConsumerStatefulWidget {
  const VesselLayer({super.key});

  /// The `CustomPaint` that draws the liquid. Its painter is a
  /// [VesselPainter]: `tester.widget<CustomPaint>(find.byKey(...)).painter`.
  static const liquidCanvasKey = ValueKey<String>('vessel-liquid');

  /// The remaining amount, the largest text on the screen.
  static const remainingKey = ValueKey<String>('vessel-remaining');

  /// The block of figures at the top; the liquid never rises into it.
  static const figuresKey = ValueKey<String>('vessel-figures');

  /// The debug-only frame-rate readout.
  static const frameRateKey = ValueKey<String>('vessel-frame-rate');

  @override
  ConsumerState<VesselLayer> createState() => _VesselLayerState();
}

class _VesselLayerState extends ConsumerState<VesselLayer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _motion = LiquidMotion();
  final _monitor = FrameTimeMonitor();
  final _frameRate = ValueNotifier<String>('');
  final _figuresKey = GlobalKey();

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  int? _lastFrameEnd;
  int _framesCounted = 0;
  double _secondsCounted = 0;

  StreamSubscription<double>? _tilt;
  ui.FragmentShader? _shader;
  bool _still = false;
  bool _resumed = true;
  bool _animateNextLevel = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addObserver(this);
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _loadShader();
    ref.listenManual(logFlowOpenProvider, (_, _) => _syncSensor());
    ref.listenManual(budgetSnapshotProvider, (_, _) {
      _animateNextLevel = true;
    });
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    WidgetsBinding.instance.removeObserver(this);
    _tilt?.cancel();
    _ticker.dispose();
    _motion.dispose();
    _frameRate.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _syncSensor();
  }

  Future<void> _loadShader() async {
    final program = await ref.read(liquidProgramLoaderProvider)();
    if (program == null || !mounted) return;
    setState(() => _shader = program.fragmentShader());
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    _motion.tick(dt);

    if (kDebugMode) {
      _framesCounted++;
      _secondsCounted += dt;
      if (_secondsCounted >= 0.5) {
        final fps = (_framesCounted / _secondsCounted).round();
        final ms = _monitor.average.inMicroseconds / 1000;
        _frameRate.value = '$fps fps · ${ms.toStringAsFixed(1)} ms';
        _framesCounted = 0;
        _secondsCounted = 0;
      }
    }
  }

  /// Feeds the monitor the time from one finished frame to the next. While
  /// the liquid is moving a frame is asked for on every vsync, so that
  /// interval is the real frame time: 16.7 ms at 60 frames per second.
  void _onTimings(List<ui.FrameTiming> timings) {
    if (_monitor.tripped || _still) {
      _lastFrameEnd = null;
      return;
    }
    for (final timing in timings) {
      final end = timing.timestampInMicroseconds(ui.FramePhase.rasterFinish);
      final previous = _lastFrameEnd;
      _lastFrameEnd = end;
      if (previous == null || end <= previous) continue;
      if (_monitor.add(Duration(microseconds: end - previous))) {
        if (mounted) ref.read(slowFramesProvider.notifier).trip();
        return;
      }
    }
  }

  /// Applies the still-water flag: stops or starts the ticker and the sensor.
  void _setStill(bool still) {
    _still = still;
    _motion.still = still;
    if (still) {
      if (_ticker.isActive) _ticker.stop();
      if (kDebugMode) _frameRate.value = 'still water';
    } else if (!_ticker.isActive) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    }
    _syncSensor();
  }

  /// Reads the sensor only while the Vessel is the top layer, the app is in
  /// the foreground and the water is not still.
  void _syncSensor() {
    final want = _resumed && !_still && !ref.read(logFlowOpenProvider);
    if (want && _tilt == null) {
      _tilt = ref
          .read(tiltSourceProvider)()
          .listen(
            _motion.setTilt,
            onError: (Object _) => _motion.releaseTilt(),
            cancelOnError: true,
          );
    } else if (!want && _tilt != null) {
      _tilt!.cancel();
      _tilt = null;
      _motion.releaseTilt();
    }
  }

  /// Sends the liquid to the height the snapshot calls for, keeping it clear
  /// of the figures. Runs after layout, when the figures' extent is known.
  void _retarget() {
    if (!mounted) return;
    final snapshot = ref.read(budgetSnapshotProvider);
    final vessel = context.findRenderObject();
    final figures = _figuresKey.currentContext?.findRenderObject();
    if (vessel is! RenderBox || figures is! RenderBox || !vessel.hasSize) {
      return;
    }
    final size = vessel.size;
    final figuresBottom = figures
        .localToGlobal(Offset(0, figures.size.height), ancestor: vessel)
        .dy;
    // Room for the surface to lean, rock and ripple without touching text.
    final clearance = LiquidMotion.maxLean * size.width / 2 + 28;
    final maxHeight = size.height - figuresBottom - clearance;

    final height = snapshot.isOverspent
        ? overspentHeight(
            overByMinor: -snapshot.remainingMinor,
            availableMinor: snapshot.availableMinor,
            screenHeight: size.height,
            maxHeight: maxHeight,
          )
        : liquidHeight(
            level: snapshot.fillLevel,
            screenHeight: size.height,
            maxHeight: maxHeight,
          );
    _motion.setLevel(height, animate: _animateNextLevel);
    _animateNextLevel = false;
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(budgetSnapshotProvider);
    final still =
        MediaQuery.disableAnimationsOf(context) ||
        ref.watch(slowFramesProvider);
    if (still != _still || (!still && !_ticker.isActive)) _setStill(still);

    _motion.setColor(TideColors.forBand(snapshot.band));
    WidgetsBinding.instance.addPostFrameCallback((_) => _retarget());

    final shader = _shader;
    final VesselPainter painter = snapshot.isOverspent
        ? OverspentBandPainter(_motion)
        : still
        ? StillLiquidPainter(_motion)
        : shader != null
        ? ShaderLiquidPainter(shader, _motion)
        : PathLiquidPainter(_motion);

    final padding = MediaQuery.paddingOf(context);
    final duration = still ? Duration.zero : const Duration(milliseconds: 600);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final contentWidth = size.width > 520 ? 520.0 : size.width;
        return Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                key: VesselLayer.liquidCanvasKey,
                painter: painter,
                size: Size.infinite,
              ),
            ),
            // The figures and pebbles normally fill the screen exactly. With
            // very large text on a very small screen they cannot, and then
            // they scroll rather than overflow.
            SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: size.height),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: contentWidth,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: size.height),
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: padding.top + 64,
                          bottom: padding.bottom + 36,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                24 + padding.left,
                                0,
                                24 + padding.right,
                                24,
                              ),
                              // The figures can change height with no
                              // rebuild here (a font arriving on web, for
                              // one), and the liquid's ceiling hangs on it.
                              child:
                                  NotificationListener<
                                    SizeChangedLayoutNotification
                                  >(
                                    onNotification: (_) {
                                      WidgetsBinding.instance
                                          .addPostFrameCallback(
                                            (_) => _retarget(),
                                          );
                                      return true;
                                    },
                                    child: SizeChangedLayoutNotifier(
                                      child: KeyedSubtree(
                                        key: _figuresKey,
                                        child: _Figures(
                                          snapshot: snapshot,
                                          duration: duration,
                                        ),
                                      ),
                                    ),
                                  ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: PebbleField(
                                categories: snapshot.categories,
                                width: contentWidth - 32,
                                duration: duration,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (kDebugMode)
              Positioned(
                left: 12 + padding.left,
                bottom: 6 + padding.bottom,
                child: _FrameRate(_frameRate),
              ),
          ],
        );
      },
    );
  }
}

/// The always-visible figures: month and mood, the remaining amount, what it
/// is left of, how full the vessel is, and what is safe to spend today.
class _Figures extends StatelessWidget {
  const _Figures({required this.snapshot, required this.duration});

  final BudgetSnapshot snapshot;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final bandColor = TideColors.forBand(s.band);
    final dot = Text('·', style: TideText.sub);
    final heroScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.35);

    return Semantics(
      container: true,
      label: vesselSemanticSummary(s),
      child: ExcludeSemantics(
        child: Column(
          key: VesselLayer.figuresKey,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 7,
              runSpacing: 2,
              children: [
                CapsText(monthName(s.now.month), style: TideText.eyebrow),
                Text('·', style: TideText.eyebrow),
                CapsText(s.moodLabel, style: TideText.eyebrow),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AnimatedDefaultTextStyle(
                duration: duration,
                style: TideText.hero.copyWith(
                  color: s.isOverspent
                      ? TideColors.overspentInk
                      : TideColors.text,
                ),
                child: Text(
                  formatRupees(s.remainingMinor),
                  key: VesselLayer.remainingKey,
                  maxLines: 1,
                  softWrap: false,
                  textScaler: heroScaler,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 2,
              children: [
                Text(
                  s.isOverspent
                      ? 'over your ${formatRupees(s.availableMinor)}'
                      : 'left of ${formatRupees(s.availableMinor)}',
                  style: TideText.sub,
                ),
                dot,
                Text('${s.fillPercent}% full', style: TideText.sub),
              ],
            ),
            const SizedBox(height: 14),
            AnimatedContainer(
              duration: duration,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: TideColors.pebbleFill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: bandColor.withValues(alpha: 0.7)),
              ),
              child: Text(
                'Safe today: ${formatRupees(s.safeToSpendTodayMinor)}',
                style: TideText.chip,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Text shown in capitals, holding its wording as written.
///
/// It is a [Text] whose [data] stays in ordinary case, so `find.text('October')`
/// finds it and a screen reader reads a word rather than spelling out
/// letters; only what is painted is upper-cased.
class CapsText extends Text {
  const CapsText(super.data, {super.key, super.style});

  @override
  Widget build(BuildContext context) =>
      Text(data!.toUpperCase(), style: style, semanticsLabel: data);
}

/// The debug-only frame-rate readout.
class _FrameRate extends StatelessWidget {
  const _FrameRate(this.text);

  final ValueListenable<String> text;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: ValueListenableBuilder<String>(
            valueListenable: text,
            builder: (context, value, _) => Text(
              value,
              key: VesselLayer.frameRateKey,
              textScaler: TextScaler.noScaling,
              style: TideText.body(size: 10, color: const Color(0x99EEF2F5)),
            ),
          ),
        ),
      ),
    );
  }
}
