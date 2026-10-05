/// Frequent-amount chips. Pure Dart.
library;

import '../budget/budget.dart';

/// The most chips ever offered.
const int maxChips = 5;

/// The expense amounts recorded most often, in paise, most frequent first.
/// Amounts recorded equally often go by the more recently used (the later
/// `occurredAt`; for the same moment, the later in [entries]). Income entries
/// are not counted. At most [limit] amounts are returned.
List<int> frequentAmounts(Iterable<Entry> entries, {int limit = maxChips}) {
  final count = <int, int>{};
  final lastUsed = <int, DateTime>{};
  final lastIndex = <int, int>{};
  var index = 0;
  for (final e in entries) {
    index++;
    if (!e.isExpense || e.amountMinor <= 0) continue;
    final a = e.amountMinor;
    count[a] = (count[a] ?? 0) + 1;
    final seen = lastUsed[a];
    if (seen == null || !e.occurredAt.isBefore(seen)) {
      lastUsed[a] = e.occurredAt;
      lastIndex[a] = index;
    }
  }
  final amounts = count.keys.toList()
    ..sort((a, b) {
      final byCount = count[b]!.compareTo(count[a]!);
      if (byCount != 0) return byCount;
      final byTime = lastUsed[b]!.compareTo(lastUsed[a]!);
      if (byTime != 0) return byTime;
      return lastIndex[b]!.compareTo(lastIndex[a]!);
    });
  return amounts.length > limit ? amounts.sublist(0, limit) : amounts;
}
