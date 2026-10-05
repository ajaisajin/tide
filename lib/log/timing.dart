/// Time-to-log maths. Pure Dart.
library;

import 'amount.dart';

/// How long one expense took to log, and with which control.
class TimingRecord {
  const TimingRecord({
    required this.entryId,
    required this.method,
    required this.elapsed,
  });

  /// The expense this record belongs to.
  final String entryId;

  /// The control that changed the amount last before filing.
  final AmountMethod method;

  /// From the log flow opening to the expense being filed.
  final Duration elapsed;

  @override
  bool operator ==(Object other) =>
      other is TimingRecord &&
      other.entryId == entryId &&
      other.method == method &&
      other.elapsed == elapsed;

  @override
  int get hashCode => Object.hash(entryId, method, elapsed);

  @override
  String toString() => 'TimingRecord($entryId, ${method.name}, $elapsed)';
}

/// The number of timed entries and their median time.
class TimingStat {
  const TimingStat({required this.count, required this.median});

  static const empty = TimingStat(count: 0, median: null);

  final int count;

  /// Null when [count] is zero.
  final Duration? median;

  @override
  bool operator ==(Object other) =>
      other is TimingStat && other.count == count && other.median == median;

  @override
  int get hashCode => Object.hash(count, median);

  @override
  String toString() => 'TimingStat($count, $median)';
}

/// Count and median for each method and for all records together.
class TimingSummary {
  const TimingSummary({required this.byMethod, required this.overall});

  final Map<AmountMethod, TimingStat> byMethod;
  final TimingStat overall;

  TimingStat of(AmountMethod method) => byMethod[method] ?? TimingStat.empty;
}

/// The median of [durations], or null when there are none. With an even
/// count it is the mean of the middle two.
Duration? medianDuration(Iterable<Duration> durations) {
  final sorted = durations.map((d) => d.inMicroseconds).toList()..sort();
  if (sorted.isEmpty) return null;
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return Duration(microseconds: sorted[mid]);
  return Duration(microseconds: (sorted[mid - 1] + sorted[mid]) ~/ 2);
}

TimingStat _stat(Iterable<TimingRecord> records) {
  final times = [for (final r in records) r.elapsed];
  return TimingStat(count: times.length, median: medianDuration(times));
}

/// Summarises [records] per method and overall.
TimingSummary summariseTimings(List<TimingRecord> records) => TimingSummary(
  byMethod: {
    for (final m in AmountMethod.values)
      m: _stat(records.where((r) => r.method == m)),
  },
  overall: _stat(records),
);

/// [d] in seconds to one decimal place, rounded to nearest: `2.4 s`.
String formatSeconds(Duration d) {
  final tenths = (d.inMicroseconds + 50000) ~/ 100000;
  return '${tenths ~/ 10}.${tenths % 10} s';
}
