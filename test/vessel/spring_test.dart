import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide/vessel/liquid_motion.dart';
import 'package:tide/vessel/spring.dart';

void run(void Function(double dt) step, double seconds) {
  const dt = 1 / 60;
  for (var t = 0.0; t < seconds; t += dt) {
    step(dt);
  }
}

void main() {
  group('DampedSpring', () {
    test('settles on its target within about one second', () {
      final spring = DampedSpring(stiffness: 90, dampingRatio: 0.7)
        ..target = 300;
      run(spring.step, 0.3);
      expect(spring.value, isNot(closeTo(300, 3)), reason: 'still travelling');
      run(spring.step, 0.8);
      expect(spring.value, closeTo(300, 0.5));
      expect(spring.isSettled(tolerance: 1), isTrue);
    });

    test('an underdamped spring overshoots, then comes back', () {
      final spring = DampedSpring(stiffness: 90, dampingRatio: 0.3)..target = 1;
      var peak = 0.0;
      run((dt) {
        spring.step(dt);
        if (spring.value > peak) peak = spring.value;
      }, 3);
      expect(peak, greaterThan(1.1));
      expect(spring.value, closeTo(1, 0.01));
    });

    test('a kick rings out and returns to rest', () {
      final spring = DampedSpring(stiffness: 120, dampingRatio: 0.42)..kick(16);
      run(spring.step, 0.1);
      expect(spring.value.abs(), greaterThan(0.3));
      run(spring.step, 1.1);
      expect(spring.value, closeTo(0, 0.02));
    });

    test('is stable when given one very long step', () {
      final spring = DampedSpring(stiffness: 120, dampingRatio: 0.42)
        ..target = 1
        ..step(5);
      expect(spring.value, closeTo(1, 0.01));
    });

    test('snap jumps to the target and stops', () {
      final spring = DampedSpring(stiffness: 90, dampingRatio: 0.7)
        ..target = 10
        ..step(0.05)
        ..snap(4);
      expect(spring.value, 4);
      expect(spring.velocity, 0);
      expect(spring.isSettled(), isTrue);
    });
  });

  group('LowPassFilter', () {
    test('moves toward the input without jumping to it', () {
      final filter = LowPassFilter(timeConstant: 0.12);
      final first = filter.step(1, 1 / 60);
      expect(first, greaterThan(0));
      expect(first, lessThan(0.2));
      for (var i = 0; i < 60; i++) {
        filter.step(1, 1 / 60);
      }
      expect(filter.value, closeTo(1, 0.01));
    });
  });

  group('LiquidMotion', () {
    const teal = Color(0xFF2BB5A6);
    const amber = Color(0xFFE9A23B);

    test('the first level is taken at once, later ones are sprung', () {
      final motion = LiquidMotion()..setLevel(300);
      expect(motion.height, 300);

      motion.setLevel(200);
      expect(motion.targetHeight, 200);
      expect(motion.height, 300, reason: 'has not moved yet');

      run(motion.tick, 0.15);
      expect(motion.height, lessThan(300));
      expect(motion.height, greaterThan(200));
      expect(motion.slosh.abs(), greaterThan(0.2), reason: 'surface disturbed');

      run(motion.tick, 1.05);
      expect(motion.height, closeTo(200, 1));
      expect(motion.slosh.abs(), lessThan(0.03));
    });

    test('a drain and a rise rock the surface opposite ways', () {
      final drain = LiquidMotion()
        ..setLevel(300)
        ..setLevel(200);
      final rise = LiquidMotion()
        ..setLevel(300)
        ..setLevel(400);
      run(drain.tick, 0.1);
      run(rise.tick, 0.1);
      expect(drain.slosh, lessThan(0));
      expect(rise.slosh, greaterThan(0));
    });

    test('tilt leans the surface, capped, and it levels when released', () {
      final motion = LiquidMotion()..setLevel(300);
      motion.setTilt(0.3);
      run(motion.tick, 1.5);
      expect(motion.lean, closeTo(0.3 * LiquidMotion.leanPerRoll, 0.005));

      motion.setTilt(1);
      run(motion.tick, 1.5);
      expect(motion.lean, closeTo(LiquidMotion.maxLean, 0.005));

      motion.releaseTilt();
      run(motion.tick, 1.5);
      expect(motion.lean, closeTo(0, 0.005));
    });

    test('the first colour is taken at once', () {
      final motion = LiquidMotion()..setColor(amber);
      expect(motion.color, amber);
    });

    test('colour cross-fades to the new band', () {
      final motion = LiquidMotion()
        ..setLevel(300)
        ..setColor(teal);
      motion.setColor(amber);
      expect(motion.targetColor, amber);
      expect(motion.color, teal);
      run(motion.tick, 0.35);
      expect(motion.color, isNot(teal));
      expect(motion.color, isNot(amber));
      run(motion.tick, 0.5);
      expect(motion.color, amber);
    });

    test('still water has no lean, slosh or waves and changes at once', () {
      final motion = LiquidMotion(color: teal)
        ..setLevel(300)
        ..setTilt(0.5);
      run(motion.tick, 0.5);
      expect(motion.lean, isNot(0));

      motion.still = true;
      expect(motion.lean, 0);
      expect(motion.slosh, 0);

      motion
        ..setLevel(120)
        ..setColor(amber)
        ..setTilt(0.9);
      final time = motion.time;
      run(motion.tick, 0.5);
      expect(motion.height, 120);
      expect(motion.color, amber);
      expect(motion.lean, 0);
      expect(motion.slosh, 0);
      expect(motion.time, time, reason: 'waves do not advance');
      expect(motion.surfaceOffset(0, 400), motion.surfaceOffset(300, 400));
    });

    test('notifies its listeners on every tick, for the repaint', () {
      final motion = LiquidMotion()..setLevel(300);
      var notified = 0;
      motion.addListener(() => notified++);
      run(motion.tick, 0.1);
      expect(notified, greaterThanOrEqualTo(6));
    });
  });
}
