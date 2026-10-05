import 'dart:math' as math;

/// A damped spring pulling [value] toward [target]. Pure Dart.
///
/// `x'' = -stiffness * (x - target) - damping * x'`, advanced with a
/// semi-implicit Euler step in slices of at most 4 ms so that it stays stable
/// whatever frame interval it is given.
class DampedSpring {
  DampedSpring({
    required this.stiffness,
    required double dampingRatio,
    double value = 0,
  }) : assert(stiffness > 0),
       assert(dampingRatio > 0),
       damping = 2 * dampingRatio * math.sqrt(stiffness),
       value = value,
       target = value;

  final double stiffness;

  /// The damping coefficient, derived from the damping ratio (1 is critical;
  /// below 1 the spring overshoots and rings).
  final double damping;

  double value;
  double velocity = 0;
  double target;

  static const _maxSlice = 0.004;

  /// Advances the spring by [dt] seconds.
  void step(double dt) {
    if (dt <= 0) return;
    final slices = (dt / _maxSlice).ceil();
    final h = dt / slices;
    for (var i = 0; i < slices; i++) {
      final acceleration = -stiffness * (value - target) - damping * velocity;
      velocity += acceleration * h;
      value += velocity * h;
    }
  }

  /// Adds [impulse] to the velocity: a knock that the spring then rings out.
  void kick(double impulse) => velocity += impulse;

  /// Jumps to [to] (or to the current target) and stops.
  void snap([double? to]) {
    if (to != null) target = to;
    value = target;
    velocity = 0;
  }

  /// True once the spring is within [tolerance] of its target and all but
  /// motionless.
  bool isSettled({double tolerance = 0.001}) =>
      (value - target).abs() <= tolerance && velocity.abs() <= tolerance * 10;
}

/// A first-order low-pass filter with a time constant in seconds. Pure Dart.
class LowPassFilter {
  LowPassFilter({required this.timeConstant, this.value = 0})
    : assert(timeConstant > 0);

  final double timeConstant;
  double value;

  /// Moves [value] toward [input] for [dt] seconds and returns it.
  double step(double input, double dt) {
    if (dt <= 0) return value;
    value += (input - value) * (1 - math.exp(-dt / timeConstant));
    return value;
  }

  void reset([double to = 0]) => value = to;
}
