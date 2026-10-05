import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../log/timing.dart';

/// The time-to-log records of this session. A test instrument: held in
/// memory, cleared from the Timings sheet.
class TimingsNotifier extends Notifier<List<TimingRecord>> {
  @override
  List<TimingRecord> build() => const [];

  void add(TimingRecord record) => state = [...state, record];

  /// Drops the record of an entry that was undone.
  void removeForEntry(String entryId) {
    state = [
      for (final r in state)
        if (r.entryId != entryId) r,
    ];
  }

  /// Forgets every record. Entries are not touched.
  void clear() => state = const [];
}

final timingsProvider = NotifierProvider<TimingsNotifier, List<TimingRecord>>(
  TimingsNotifier.new,
);

/// Count and median per method and overall.
final timingSummaryProvider = Provider<TimingSummary>(
  (ref) => summariseTimings(ref.watch(timingsProvider)),
);
