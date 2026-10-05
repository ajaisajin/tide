import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide/log/amount.dart';
import 'package:tide/log/timing.dart';
import 'package:tide/state/budget_state.dart';
import 'package:tide/state/timing_state.dart';

Duration secs(double s) => Duration(milliseconds: (s * 1000).round());

TimingRecord rec(String id, AmountMethod m, double s) =>
    TimingRecord(entryId: id, method: m, elapsed: secs(s));

final scenario = [
  rec('a', AmountMethod.pad, 2.1),
  rec('b', AmountMethod.pad, 3.4),
  rec('c', AmountMethod.ring, 4.0),
  rec('d', AmountMethod.pad, 2.6),
];

void main() {
  group('median', () {
    test('none', () => expect(medianDuration(const []), isNull));
    test('one', () => expect(medianDuration([secs(4)]), secs(4)));
    test('odd count takes the middle', () {
      expect(medianDuration([secs(3.4), secs(2.1), secs(2.6)]), secs(2.6));
    });
    test('even count takes the mean of the middle two', () {
      expect(
        medianDuration([secs(4.0), secs(2.1), secs(3.4), secs(2.6)]),
        secs(3.0),
      );
    });
  });

  group('summary', () {
    test('median per method: pad 3 at 2.6 s, ring 1 at 4.0 s, overall 4 at '
        '3.0 s', () {
      final s = summariseTimings(scenario);
      expect(s.of(AmountMethod.pad), TimingStat(count: 3, median: secs(2.6)));
      expect(s.of(AmountMethod.ring), TimingStat(count: 1, median: secs(4.0)));
      expect(s.of(AmountMethod.chips), TimingStat.empty);
      expect(s.overall, TimingStat(count: 4, median: secs(3.0)));
      expect(formatSeconds(s.of(AmountMethod.pad).median!), '2.6 s');
      expect(formatSeconds(s.of(AmountMethod.ring).median!), '4.0 s');
      expect(formatSeconds(s.overall.median!), '3.0 s');
    });

    test('nothing recorded: all counts zero, no medians', () {
      final s = summariseTimings(const []);
      for (final m in AmountMethod.values) {
        expect(s.of(m), TimingStat.empty);
      }
      expect(s.overall, TimingStat.empty);
    });
  });

  group('formatSeconds', () {
    test('one decimal place, rounded to nearest', () {
      expect(formatSeconds(secs(2.4)), '2.4 s');
      expect(formatSeconds(secs(2.44)), '2.4 s');
      expect(formatSeconds(secs(2.45)), '2.5 s');
      expect(formatSeconds(secs(0)), '0.0 s');
      expect(formatSeconds(secs(12.96)), '13.0 s');
    });
  });

  group('timings state', () {
    test('an undone entry leaves the summary', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final t = c.read(timingsProvider.notifier);
      scenario.forEach(t.add);
      expect(c.read(timingSummaryProvider).overall.count, 4);

      t.removeForEntry('b');
      final s = c.read(timingSummaryProvider);
      expect(s.of(AmountMethod.pad), TimingStat(count: 2, median: secs(2.35)));
      expect(s.overall, TimingStat(count: 3, median: secs(2.6)));
    });

    test('clearing zeroes every count and leaves entries alone', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final entries = c.read(budgetProvider).entries;
      scenario.forEach(c.read(timingsProvider.notifier).add);
      c.read(timingsProvider.notifier).clear();
      final s = c.read(timingSummaryProvider);
      expect(s.overall.count, 0);
      for (final m in AmountMethod.values) {
        expect(s.of(m).count, 0);
      }
      expect(c.read(budgetProvider).entries, entries);
    });
  });
}
