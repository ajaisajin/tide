import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/tide_theme.dart';
import 'ring_tracker.dart';

/// The amount ring: drag a finger around it, clockwise to raise the amount
/// and anticlockwise to lower it. The faster the turn, the bigger the step.
///
/// It reports each step through [onStep] as a signed number of rupees and
/// leaves clamping, and the haptic tick, to its owner.
class AmountRing extends StatefulWidget {
  const AmountRing({
    super.key,
    required this.onStep,
    this.color = TideColors.teal,
  });

  final ValueChanged<int> onStep;
  final Color color;

  /// Touches closer to the centre than this fraction of the radius are
  /// ignored: the angle is too jumpy there.
  static const double deadZone = 0.3;

  @override
  State<AmountRing> createState() => _AmountRingState();
}

class _AmountRingState extends State<AmountRing> {
  final _tracker = RingTracker();
  final _turned = ValueNotifier<double>(0);
  final _stepSize = ValueNotifier<int>(0);
  int? _pointer;

  @override
  void dispose() {
    _turned.dispose();
    _stepSize.dispose();
    super.dispose();
  }

  void _track(PointerEvent event) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final local = box.globalToLocal(event.position);
    final v = local - box.size.center(Offset.zero);
    final radius = box.size.shortestSide / 2;
    if (v.distance < radius * AmountRing.deadZone) {
      _tracker.end();
      return;
    }
    final angle = math.atan2(v.dy, v.dx);
    final seconds = event.timeStamp.inMicroseconds / 1e6;
    if (!_tracker.isTracking) {
      _tracker.start(angle, seconds);
      return;
    }
    final steps = _tracker.update(angle, seconds);
    _turned.value = _tracker.turned;
    for (final step in steps) {
      _stepSize.value = step.abs();
      widget.onStep(step);
    }
  }

  void _down(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _track(event);
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer == _pointer) _track(event);
  }

  void _up(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _tracker.end();
    _stepSize.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label:
          'Amount ring. Turn clockwise to raise the amount, '
          'anticlockwise to lower it',
      onIncrease: () => widget.onStep(RingTracker.slowStepRupees),
      onDecrease: () => widget.onStep(-RingTracker.slowStepRupees),
      child: ExcludeSemantics(
        // Claims the touch at once, so turning the ring never scrolls the
        // log flow on a screen small enough to need scrolling.
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            EagerGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                  EagerGestureRecognizer.new,
                  (_) {},
                ),
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _up,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _RingPainter(_turned, widget.color),
                child: Center(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _stepSize,
                    builder: (context, step, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          step == 0 ? 'Turn the ring' : '₹$step steps',
                          style: TideText.body(
                            size: 14,
                            weight: FontWeight.w600,
                            color: TideColors.soft,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text('faster for bigger steps', style: TideText.hint),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.turned, this.color) : super(repaint: turned);

  final ValueListenable<double> turned;
  final Color color;

  static const double _stroke = 30;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - _stroke / 2 - 2;
    if (radius <= 0) return;

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..color = const Color(0x1AEEF2F5),
    );

    // Notches that go round with the finger, one per step.
    final notch = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x40EEF2F5);
    const notches = 24;
    for (var i = 0; i < notches; i++) {
      final a = turned.value + i * 2 * math.pi / notches;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        centre + dir * (radius - 5),
        centre + dir * (radius + 5),
        notch,
      );
    }

    // The grip: a bright arc with a knob, starting at twelve o'clock.
    final grip = -math.pi / 2 + turned.value;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      grip - 0.42,
      0.84,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    canvas.drawCircle(
      centre + Offset(math.cos(grip), math.sin(grip)) * radius,
      7,
      Paint()..color = TideColors.ink,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.turned != turned || old.color != color;
}
