import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide/state/clock.dart';
import 'package:tide/state/today.dart';

import '../support/log_helpers.dart';

void main() {
  // Each test disposes its container itself: the pending midnight timer has
  // to be gone before the test body returns.
  (ProviderContainer, List<DateTime>) watch(TestClock clock) {
    final c = ProviderContainer(
      overrides: [clockProvider.overrideWithValue(clock.call)],
    );
    final seen = <DateTime>[];
    c.listen(todayProvider, (_, next) => seen.add(next));
    return (c, seen);
  }

  /// Moves the clock and the timers on together.
  Future<void> pass(WidgetTester tester, TestClock clock, Duration d) async {
    clock.advance(d);
    await tester.pump(d);
  }

  testWidgets('is the clock\'s date, at midnight', (tester) async {
    final (c, seen) = watch(TestClock(DateTime(2026, 10, 5, 10, 30)));
    expect(c.read(todayProvider), DateTime(2026, 10, 5));
    expect(seen, isEmpty);
    c.dispose();
  });

  testWidgets('moves on at each local midnight', (tester) async {
    final clock = TestClock(DateTime(2026, 10, 30, 23, 59, 30));
    final (c, seen) = watch(clock);

    await pass(tester, clock, const Duration(seconds: 29));
    expect(seen, isEmpty);
    await pass(tester, clock, const Duration(seconds: 1));
    expect(seen, [DateTime(2026, 10, 31)]);

    // The timer was set again, and this midnight is also a month end.
    await pass(tester, clock, const Duration(hours: 24));
    expect(seen, [DateTime(2026, 10, 31), DateTime(2026, 11, 1)]);
    expect(c.read(todayProvider), DateTime(2026, 11, 1));
    c.dispose();
  });

  testWidgets('a timer that fires early changes nothing and waits again', (
    tester,
  ) async {
    final clock = TestClock(DateTime(2026, 10, 5, 23, 59, 30));
    final (c, seen) = watch(clock);

    // Thirty seconds pass for the timer, twenty on the clock.
    clock.advance(const Duration(seconds: 20));
    await tester.pump(const Duration(seconds: 30));
    expect(seen, isEmpty);

    await pass(tester, clock, const Duration(seconds: 10));
    expect(c.read(todayProvider), DateTime(2026, 10, 6));
    c.dispose();
  });

  testWidgets('reads the clock again when the app returns to the '
      'foreground', (tester) async {
    final clock = TestClock(DateTime(2026, 10, 30, 18));
    final (c, seen) = watch(clock);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    clock.now = DateTime(2026, 11, 2, 8);
    expect(c.read(todayProvider), DateTime(2026, 10, 30));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(seen, [DateTime(2026, 11, 2)]);

    // Coming back on the same day says nothing.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    clock.advance(const Duration(hours: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(seen, hasLength(1));
    c.dispose();
  });
}
