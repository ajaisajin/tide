/// Turns a finger moving around the amount ring into amount steps. Pure Dart.
library;

import 'dart:math' as math;

/// Tracks the angle of a finger around the ring's centre and reports the
/// amount steps it has earned.
///
/// Angles are in radians as `atan2(dy, dx)` gives them in screen coordinates
/// (y pointing down), so a growing angle is a clockwise turn and raises the
/// amount. Every [stepAngle] of travel is one step; how much the step is worth
/// depends on how fast the finger is going round at that moment.
class RingTracker {
  /// Travel around the ring for one step: 15 degrees, 24 steps a turn.
  static const double stepAngle = math.pi / 12;

  /// Angular speed, in radians per second, from which a step is worth
  /// [mediumStepRupees]: a little under half a turn per second.
  static const double mediumSpeed = 2.5;

  /// Angular speed, in radians per second, from which a step is worth
  /// [fastStepRupees]: about one turn per second.
  static const double fastSpeed = 6.0;

  static const int slowStepRupees = 10;
  static const int mediumStepRupees = 100;
  static const int fastStepRupees = 1000;

  /// Seconds over which the measured speed is smoothed, so one jittery
  /// sample does not change the step size.
  static const double smoothingSeconds = 0.08;

  /// The step size in rupees for an angular [speed] in radians per second.
  static int stepRupeesFor(double speed) {
    final s = speed.abs();
    if (s >= fastSpeed) return fastStepRupees;
    if (s >= mediumSpeed) return mediumStepRupees;
    return slowStepRupees;
  }

  double? _lastAngle;
  double _lastSeconds = 0;
  double _pending = 0;
  double _speed = 0;
  bool _hasSpeed = false;
  double _turned = 0;

  /// Whether a turn is being tracked.
  bool get isTracking => _lastAngle != null;

  /// The smoothed angular speed in radians per second, always positive.
  double get speed => _speed;

  /// The total angle turned since the tracker was made, clockwise positive.
  /// Only for drawing the ring's position.
  double get turned => _turned;

  /// The finger touches the ring at [angle], at [seconds] on any clock.
  void start(double angle, double seconds) {
    _lastAngle = angle;
    _lastSeconds = seconds;
    _pending = 0;
    _speed = 0;
    _hasSpeed = false;
  }

  /// The finger has moved to [angle] at [seconds]. Returns the steps earned
  /// since the last call, in order, each a signed number of rupees: positive
  /// for clockwise, negative for anticlockwise.
  List<int> update(double angle, double seconds) {
    final last = _lastAngle;
    if (last == null) {
      start(angle, seconds);
      return const [];
    }
    final delta = shortestTurn(last, angle);
    final dt = seconds - _lastSeconds;
    _lastAngle = angle;
    _lastSeconds = seconds;
    _turned += delta;

    if (dt > 0) {
      final instant = delta.abs() / dt;
      if (_hasSpeed) {
        final weight = math.min(1.0, dt / smoothingSeconds);
        _speed += (instant - _speed) * weight;
      } else {
        _speed = instant;
        _hasSpeed = true;
      }
    }

    // Reversing direction throws away the part-step earned the other way.
    if (_pending != 0 && delta != 0 && _pending.sign != delta.sign) {
      _pending = 0;
    }
    _pending += delta;

    final steps = <int>[];
    // The tiny allowance keeps twelve 15-degree moves at twelve steps despite
    // floating-point error.
    while (_pending.abs() >= stepAngle - 1e-9) {
      final sign = _pending > 0 ? 1 : -1;
      steps.add(sign * stepRupeesFor(_speed));
      _pending -= sign * stepAngle;
    }
    return steps;
  }

  /// The finger has lifted.
  void end() {
    _lastAngle = null;
    _pending = 0;
    _speed = 0;
    _hasSpeed = false;
  }

  /// The signed shortest way round from angle [from] to angle [to], in
  /// (-pi, pi], so crossing the atan2 seam does not read as a full turn back.
  static double shortestTurn(double from, double to) {
    var d = (to - from) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    return d;
  }
}
