import 'package:flutter_test/flutter_test.dart';
import 'package:tide/vessel/frame_monitor.dart';
import 'package:tide/vessel/vessel_geometry.dart';

void main() {
  group('liquidHeight', () {
    test('runs from the 8% floor to the 70% ceiling', () {
      double at(double level) => liquidHeight(level: level, screenHeight: 1000);
      expect(at(0), closeTo(80, 1e-9));
      expect(at(0.02), closeTo(92.4, 1e-9));
      expect(at(0.5), closeTo(390, 1e-9));
      expect(at(1), closeTo(700, 1e-9));
    });

    test('still shows a band at level 0 and 0.02', () {
      expect(liquidHeight(level: 0, screenHeight: 568), greaterThan(40));
      expect(
        liquidHeight(level: 0.02, screenHeight: 568),
        greaterThan(liquidHeight(level: 0, screenHeight: 568)),
      );
    });

    test('clamps levels outside 0 to 1', () {
      expect(liquidHeight(level: -1, screenHeight: 1000), closeTo(80, 1e-9));
      expect(liquidHeight(level: 3, screenHeight: 1000), closeTo(700, 1e-9));
    });

    test('the ceiling comes down to the room left under the text', () {
      double at(double level) =>
          liquidHeight(level: level, screenHeight: 1000, maxHeight: 500);
      expect(at(1), closeTo(500, 1e-9));
      expect(at(0), closeTo(80, 1e-9));
      expect(at(0.5), closeTo(290, 1e-9), reason: 'still linear');
      expect(
        liquidHeight(level: 1, screenHeight: 1000, maxHeight: 900),
        closeTo(700, 1e-9),
        reason: 'spare room does not raise the ceiling',
      );
    });

    test('keeps a little range even when the text leaves no room', () {
      final empty = liquidHeight(level: 0, screenHeight: 500, maxHeight: -40);
      final full = liquidHeight(level: 1, screenHeight: 500, maxHeight: -40);
      expect(empty, closeTo(40, 1e-9));
      expect(full, greaterThan(empty));
    });
  });

  group('overspentHeight', () {
    double at(int overBy) => overspentHeight(
      overByMinor: overBy,
      availableMinor: 3000000,
      screenHeight: 1000,
    );

    test('starts at 6% and grows with the overspend', () {
      expect(at(0), closeTo(60, 1e-9));
      expect(at(200000), closeTo(60 + 2 / 30 * 400, 1e-6));
      expect(at(600000), greaterThan(at(200000)));
    });

    test('stops growing at half the amount available', () {
      expect(at(1500000), closeTo(260, 1e-9));
      expect(at(9000000), closeTo(260, 1e-9));
    });

    test('copes with nothing available', () {
      expect(
        overspentHeight(
          overByMinor: 100,
          availableMinor: 0,
          screenHeight: 1000,
        ),
        closeTo(260, 1e-9),
      );
    });
  });

  group('pebbleDiameter', () {
    test('grows with the share of the limit from a 64 pixel minimum', () {
      expect(pebbleDiameter(0), 64);
      expect(pebbleDiameter(0.33), closeTo(64 + 0.33 * 34, 1e-9));
      expect(pebbleDiameter(0.9), greaterThan(pebbleDiameter(0.33)));
      expect(pebbleDiameter(1), 98);
    });

    test('stops growing past the limit and never goes below 64', () {
      expect(pebbleDiameter(1.4), 98);
      expect(pebbleDiameter(-0.5), 64);
      expect(pebbleDiameter(double.nan), 64);
      expect(pebbleDiameter(0.9, growth: 0), 64);
      expect(pebbleDiameter(0.9, growth: -10), 64);
    });

    test('growth shrinks so three fit across a narrow screen', () {
      expect(pebbleGrowthFor(380), 34);
      final narrow = pebbleGrowthFor(288);
      expect(narrow, lessThan(34));
      expect(3 * pebbleDiameter(1, growth: narrow) + 20, closeTo(288, 1e-9));
      expect(pebbleGrowthFor(100), 0);
    });
  });

  test('month names', () {
    expect(monthName(1), 'January');
    expect(monthName(10), 'October');
    expect(monthName(12), 'December');
  });

  group('FrameTimeMonitor', () {
    const ms16 = Duration(milliseconds: 16);
    const ms25 = Duration(milliseconds: 25);

    test('trips after two seconds of 25 ms frames', () {
      final monitor = FrameTimeMonitor();
      var frames = 0;
      while (!monitor.add(ms25)) {
        frames++;
        expect(frames, lessThan(200), reason: 'never tripped');
      }
      // 80 frames of 25 ms make two seconds.
      expect(frames + 1, 80);
      expect(monitor.tripped, isTrue);
    });

    test('has not tripped after 1.9 seconds of 25 ms frames', () {
      final monitor = FrameTimeMonitor();
      for (var i = 0; i < 76; i++) {
        monitor.add(ms25);
      }
      expect(monitor.tripped, isFalse);
    });

    test('does not trip on 16 ms frames', () {
      final monitor = FrameTimeMonitor();
      for (var i = 0; i < 2000; i++) {
        expect(monitor.add(ms16), isFalse);
      }
      expect(monitor.tripped, isFalse);
      expect(monitor.average, ms16);
    });

    test('a short spike does not trip it', () {
      final monitor = FrameTimeMonitor();
      for (var round = 0; round < 20; round++) {
        for (var i = 0; i < 100; i++) {
          monitor.add(ms16);
        }
        // Three bad frames, one of them a long freeze.
        monitor
          ..add(const Duration(milliseconds: 120))
          ..add(const Duration(seconds: 3))
          ..add(const Duration(milliseconds: 60));
      }
      expect(monitor.tripped, isFalse);
    });

    test('a slow spell that recovers starts the count again', () {
      final monitor = FrameTimeMonitor();
      for (var round = 0; round < 5; round++) {
        for (var i = 0; i < 60; i++) {
          monitor.add(ms25); // 1.5 s slow
        }
        for (var i = 0; i < 120; i++) {
          monitor.add(ms16);
        }
      }
      expect(monitor.tripped, isFalse);
    });

    test('stays tripped', () {
      final monitor = FrameTimeMonitor();
      for (var i = 0; i < 100; i++) {
        monitor.add(ms25);
      }
      expect(monitor.tripped, isTrue);
      for (var i = 0; i < 1000; i++) {
        expect(monitor.add(ms16), isFalse);
      }
      expect(monitor.tripped, isTrue);
    });
  });
}
