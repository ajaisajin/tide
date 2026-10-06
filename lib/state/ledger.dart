import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../budget/budget.dart';
import '../log/chips.dart';
import '../storage/storage.dart';

/// What the app reads from the saved ledger before its first frame, so that
/// every screen can go on reading state synchronously.
class LedgerStart {
  LedgerStart({
    required this.month,
    required List<Entry> entries,
    required List<Category> categories,
    required this.budgetMinor,
    required this.hasBudget,
    required this.incomeMinor,
    required List<int> frequentAmountsMinor,
  }) : entries = List.unmodifiable(entries),
       categories = List.unmodifiable(categories),
       frequentAmountsMinor = List.unmodifiable(frequentAmountsMinor);

  /// The local calendar month the data was loaded for.
  final YearMonth month;

  /// That month's entries, oldest first.
  final List<Entry> entries;

  /// Categories in display order.
  final List<Category> categories;

  /// The budget in force for [month], in paise; null when none applies.
  final int? budgetMinor;

  /// Whether a budget has been set for any month, which is what "setup has
  /// been completed" means.
  final bool hasBudget;

  /// The saved monthly income in paise; null when none has been saved.
  final int? incomeMinor;

  /// The frequent-amount chips, most frequent first, over every month.
  final List<int> frequentAmountsMinor;
}

/// Reads from [store] everything the app shows at [now].
Future<LedgerStart> loadLedgerStart(LedgerStore store, DateTime now) async {
  final month = YearMonth.of(now);
  final (entries, categories, budget, hasBudget, profile, frequent) = await (
    store.entriesForMonth(month),
    store.loadCategories(),
    store.budgetFor(month),
    store.hasAnyBudget(),
    store.loadProfile(),
    store.frequentExpenseAmounts(limit: maxChips),
  ).wait;
  return LedgerStart(
    month: month,
    entries: entries,
    categories: categories,
    budgetMinor: budget,
    hasBudget: hasBudget,
    incomeMinor: profile?.monthlyIncomeMinor,
    frequentAmountsMinor: frequent,
  );
}

/// The open ledger. `main()` opens it before `runApp` and passes it in as an
/// override; there is no default.
final ledgerStoreProvider = Provider<LedgerStore>(
  (ref) => throw StateError('ledgerStoreProvider has not been overridden'),
);

/// What was loaded from the ledger at start-up. Passed in as an override
/// beside [ledgerStoreProvider]; there is no default.
final ledgerStartProvider = Provider<LedgerStart>(
  (ref) => throw StateError('ledgerStartProvider has not been overridden'),
);

/// The two overrides the app cannot run without. [start] comes from
/// [loadLedgerStart] on the same [store].
List<Override> ledgerOverrides(LedgerStore store, LedgerStart start) => [
  ledgerStoreProvider.overrideWithValue(store),
  ledgerStartProvider.overrideWithValue(start),
];

/// The frequent-amount chips: the expense amounts recorded most often across
/// the whole ledger, in paise. Loaded at start-up and asked for again after
/// each write, so reading them never waits.
class FrequentAmountsNotifier extends Notifier<List<int>> {
  @override
  List<int> build() => ref.watch(ledgerStartProvider).frequentAmountsMinor;

  /// Asks the store again. If that fails the chips stay as they were: they
  /// are a convenience, and the write they follow has already been saved.
  Future<void> refresh() async {
    try {
      final amounts = await ref
          .read(ledgerStoreProvider)
          .frequentExpenseAmounts(limit: maxChips);
      if (ref.mounted) state = List.unmodifiable(amounts);
    } catch (_) {
      // Keep the chips on show.
    }
  }
}

final frequentAmountsProvider =
    NotifierProvider<FrequentAmountsNotifier, List<int>>(
      FrequentAmountsNotifier.new,
    );
