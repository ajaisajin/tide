import 'package:flutter_test/flutter_test.dart';
import 'package:tide/dev/start_timing_io.dart';

void main() {
  test(
    'the time since the process started is the clock less its start time',
    () {
      // As read on the emulator: started 1,180.79 s after boot.
      const stat =
          '9664 (cat) R 532 9664 9664 0 -1 4194304 865 0 0 0 0 0 0 0 20 0 1 0 '
          '118079 11050835968 1158 18446744073709551615 1 1 0 0 0 0 0 0';
      expect(millisecondsBetween(stat: stat, monotonicMicros: 1181210400), 420);
    },
  );

  test('a process name with spaces and brackets does not shift the fields', () {
    const stat =
        '41 (a (b) c) S 1 41 41 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 '
        '500 1 1 1 1 1 0 0 0 0 0 0';
    expect(millisecondsBetween(stat: stat, monotonicMicros: 6500000), 1500);
  });

  test('on this machine it reads a small, positive time', () {
    final ms = millisecondsSinceProcessStart();
    expect(ms, isNotNull);
    expect(ms, greaterThanOrEqualTo(0));
    expect(ms, lessThan(const Duration(hours: 1).inMilliseconds));
  });
}
