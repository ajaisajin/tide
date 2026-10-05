import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'spring.dart';

/// Everything the liquid painters draw from, advanced once per frame.
///
/// It is a [ChangeNotifier] handed to the painters as their `repaint`
/// listenable, so a change repaints the canvas without rebuilding a widget.
/// Nothing here touches the widget tree, the ticker or the sensor: the Vessel
/// calls [tick], [setLevel], [setColor] and [setTilt].
class LiquidMotion extends ChangeNotifier {
  LiquidMotion({Color color = const Color(0xFF2BB5A6)})
    : _colorFrom = color,
      _colorTo = color,
      _color = color;

  /// The steepest the surface may lean, as a slope (rise over run).
  static const double maxLean = 0.16;

  /// Lean per unit of roll, where roll is sideways gravity divided by g.
  static const double leanPerRoll = 0.32;

  /// The idle wave amplitude in logical pixels.
  static const double idleAmplitude = 2.4;

  /// Extra wave amplitude, in logical pixels, per unit of slosh.
  static const double sloshAmplitude = 7.0;

  /// How far, in logical pixels, a slosh of 1 lifts the surface at one edge
  /// (and drops it at the other).
  static const double sloshRock = 16.0;

  /// The wave phase repeats after this many seconds, which keeps the number
  /// sent to the shader small. Every wave speed is a multiple of 0.1 rad/s.
  static const double timePeriod = 20 * math.pi;

  static const double _colorSeconds = 0.7;

  final DampedSpring _fill = DampedSpring(stiffness: 90, dampingRatio: 0.7);
  final DampedSpring _lean = DampedSpring(stiffness: 90, dampingRatio: 0.55);
  final DampedSpring _slosh = DampedSpring(stiffness: 120, dampingRatio: 0.42);
  final LowPassFilter _tilt = LowPassFilter(timeConstant: 0.12);

  double _rawRoll = 0;
  double _time = 0;
  bool _still = false;
  bool _hasLevel = false;
  bool _hasColor = false;

  Color _colorFrom;
  Color _colorTo;
  Color _color;
  double _colorT = 1;

  /// The liquid's current height above the bottom edge, in logical pixels.
  double get height => _fill.value;

  /// The height the liquid is heading for.
  double get targetHeight => _fill.target;

  /// The surface slope: positive means the surface is higher on the left.
  double get lean => _still ? 0 : _lean.value;

  /// The disturbance of the surface, signed; zero when calm.
  double get slosh => _still ? 0 : _slosh.value;

  /// Seconds of wave phase, wrapped at [timePeriod].
  double get time => _time;

  /// The liquid's current colour, part-way through a change of band.
  Color get color => _color;

  /// The colour the liquid is heading for.
  Color get targetColor => _colorTo;

  /// Still water: a flat level with no waves, lean or slosh. Level and colour
  /// changes are applied at once instead of being animated.
  bool get still => _still;
  set still(bool value) {
    if (_still == value) return;
    _still = value;
    if (value) {
      _fill.snap();
      _lean.snap(0);
      _slosh.snap(0);
      _tilt.reset();
      _rawRoll = 0;
      _color = _colorTo;
      _colorT = 1;
    }
    notifyListeners();
  }

  /// Sends the liquid to [height] logical pixels. With [animate] it springs
  /// there and the surface sloshes; without (or in still water, or the first
  /// time) it jumps.
  void setLevel(double height, {bool animate = true}) {
    // Already heading there: leave any spring in flight alone.
    if (_hasLevel && !_still && _fill.target == height) return;
    if (!_hasLevel || !animate || _still) {
      _hasLevel = true;
      if (_fill.value == height && _fill.target == height) return;
      _fill.snap(height);
      notifyListeners();
      return;
    }
    final change = height - _fill.target;
    _fill.target = height;
    // A bigger change knocks the surface harder; a drain rocks it the other
    // way from a rise.
    final strength = (0.5 + change.abs() / 120).clamp(0.5, 1.3);
    _slosh.kick((change > 0 ? 1 : -1) * strength * 16);
  }

  /// Sends the colour to [color], cross-fading unless [animate] is false, the
  /// water is still, or this is the first colour it has been given.
  void setColor(Color color, {bool animate = true}) {
    final first = !_hasColor;
    _hasColor = true;
    if (color == _colorTo) return;
    if (first || !animate || _still) {
      _colorFrom = _colorTo = _color = color;
      _colorT = 1;
      notifyListeners();
      return;
    }
    _colorFrom = _color;
    _colorTo = color;
    _colorT = 0;
  }

  /// Takes a sensor reading: [roll] is sideways gravity divided by g, positive
  /// when the phone's left edge is the lower one. Ignored in still water.
  void setTilt(double roll) {
    if (_still || roll.isNaN) return;
    _rawRoll = roll.clamp(-1.0, 1.0);
  }

  /// Lets the surface settle level again, for when the sensor stops.
  void releaseTilt() => _rawRoll = 0;

  /// Advances the motion by [dt] seconds and repaints.
  void tick(double dt) {
    if (_still || dt <= 0) return;
    final step = math.min(dt, 0.05);
    _time = (_time + step) % timePeriod;

    final roll = _tilt.step(_rawRoll, step);
    _lean.target = (roll * leanPerRoll).clamp(-maxLean, maxLean);

    _fill.step(step);
    _lean.step(step);
    _slosh.step(step);
    if (_fill.value < 0) _fill.value = 0;

    if (_colorT < 1) {
      _colorT = math.min(1, _colorT + step / _colorSeconds);
      final eased = _colorT * _colorT * (3 - 2 * _colorT);
      _color = Color.lerp(_colorFrom, _colorTo, eased)!;
    }
    notifyListeners();
  }

  /// Ripples at horizontal position [x], in logical pixels, positive downward:
  /// a few summed sines, larger while the surface is disturbed. The fragment
  /// shader computes the same thing; this copy serves the fallback painter.
  double ripple(double x, {double phase = 0}) {
    if (_still) return 0;
    final amplitude = idleAmplitude + slosh.abs() * sloshAmplitude;
    final t = _time + phase;
    return amplitude *
        (0.55 * math.sin(x * 0.030 + t * 1.1) +
            0.30 * math.sin(x * 0.065 - t * 1.7) +
            0.15 * math.sin(x * 0.018 + t * 0.6));
  }

  /// The lean and the rocking of the whole surface at [x] across [width], in
  /// logical pixels, positive downward.
  double slope(double x, double width) {
    if (_still) return 0;
    final u = width > 0 ? x / width : 0.5;
    return lean * (x - width / 2) + slosh * sloshRock * math.cos(math.pi * u);
  }

  /// The front surface's offset from the flat level at [x].
  double surfaceOffset(double x, double width) => slope(x, width) + ripple(x);
}
