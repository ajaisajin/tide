import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tide/log/ring_tracker.dart';

/// Turns [tracker] at [speed] radians per second (negative is anticlockwise)
/// for [seconds], sampled 60 times a second, and returns every step.
List<int> turn(
  RingTracker tracker, {
  required double speed,
  required double seconds,
  double from = 0,
  double startTime = 0,
}) {
  const dt = 1 / 60;
  final steps = <int>[];
  double wrap(double a) => math.atan2(math.sin(a), math.cos(a));
  if (!tracker.isTracking) tracker.start(wrap(from), startTime);
  final samples = (seconds / dt).round();
  for (var i = 1; i <= samples; i++) {
    steps.addAll(
      tracker.update(wrap(from + speed * i * dt), startTime + i * dt),
    );
  }
  return steps;
}

void main() {
  test('the thresholds and step sizes are the named constants', () {
    expect(RingTracker.slowStepRupees, 10);
    expect(RingTracker.mediumStepRupees, 100);
    expect(RingTracker.fastStepRupees, 1000);
    expect(RingTracker.mediumSpeed, lessThan(RingTracker.fastSpeed));
    expect(RingTracker.stepRupeesFor(0), 10);
    expect(RingTracker.stepRupeesFor(RingTracker.mediumSpeed - 0.01), 10);
    expect(RingTracker.stepRupeesFor(RingTracker.mediumSpeed), 100);
    expect(RingTracker.stepRupeesFor(RingTracker.fastSpeed - 0.01), 100);
    expect(RingTracker.stepRupeesFor(RingTracker.fastSpeed), 1000);
    expect(RingTracker.stepRupeesFor(-RingTracker.fastSpeed), 1000);
  });

  test('a slow clockwise turn steps by ₹10', () {
    // A quarter turn in about a second and a half.
    final steps = turn(RingTracker(), speed: 1.0, seconds: math.pi / 2 + 0.01);
    expect(steps, List.filled(6, 10));
  });

  test('a medium clockwise turn steps by ₹100', () {
    final steps = turn(RingTracker(), speed: 4.0, seconds: 1);
    expect(steps, isNotEmpty);
    expect(steps.toSet(), {100});
    expect(steps.length, (4.0 / RingTracker.stepAngle).floor());
  });

  test('a fast clockwise spin steps by ₹1,000', () {
    final steps = turn(RingTracker(), speed: 9.0, seconds: 1);
    expect(steps, isNotEmpty);
    expect(steps.toSet(), {1000});
  });

  test('anticlockwise lowers, at each speed', () {
    expect(turn(RingTracker(), speed: -1.0, seconds: 1).toSet(), {-10});
    expect(turn(RingTracker(), speed: -4.0, seconds: 1).toSet(), {-100});
    expect(turn(RingTracker(), speed: -9.0, seconds: 1).toSet(), {-1000});
  });

  test('one step per 15 degrees of travel, across the atan2 seam', () {
    // Start just before the seam at 180 degrees and go a full turn.
    final steps = turn(
      RingTracker(),
      speed: 1.5,
      seconds: 2 * math.pi / 1.5 + 0.01,
      from: math.pi - 0.2,
    );
    expect(steps, List.filled(24, 10));
  });

  test('slowing down mid-turn brings the step size back down', () {
    final tracker = RingTracker();
    final fast = turn(tracker, speed: 9.0, seconds: 0.5);
    final slow = turn(
      tracker,
      speed: 1.0,
      seconds: 1.5,
      from: 4.5,
      startTime: 0.5,
    );
    expect(fast.toSet(), {1000});
    expect(slow.last, 10);
  });

  test('reversing discards the part-step earned the other way', () {
    final tracker = RingTracker()..start(0, 0);
    expect(tracker.update(0.2, 0.2), isEmpty); // 11 of 15 degrees clockwise
    expect(tracker.update(0.1, 0.4), isEmpty); // back a little: no step
    expect(tracker.update(0.1 - RingTracker.stepAngle, 0.9), [-10]);
  });

  test('a finger that does not move earns nothing', () {
    final tracker = RingTracker()..start(1, 0);
    expect(tracker.update(1, 0.5), isEmpty);
    expect(tracker.update(1, 1.0), isEmpty);
  });

  test('lifting the finger forgets the turn in progress', () {
    final tracker = RingTracker()..start(0, 0);
    tracker.update(0.2, 0.2);
    tracker.end();
    expect(tracker.isTracking, isFalse);
    tracker.start(2.0, 5);
    expect(tracker.update(2.1, 5.1), isEmpty);
  });

  test('shortestTurn takes the short way round', () {
    expect(RingTracker.shortestTurn(3.0, -3.0), closeTo(0.283, 0.001));
    expect(RingTracker.shortestTurn(-3.0, 3.0), closeTo(-0.283, 0.001));
    expect(RingTracker.shortestTurn(0, 1), closeTo(1, 1e-9));
  });
}
