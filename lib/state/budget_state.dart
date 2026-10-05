import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../budget/budget.dart';
import 'clock.dart';
import 'ids.dart';
import 'seed.dart';

/// The budget, the categories and every entry. Held in memory only.
class BudgetState {
  BudgetState({
    required this.budgetMinor,
    required List<Category> categories,
    required List<Entry> entries,
  }) : categories = List.unmodifiable(categories),
       entries = List.unmodifiable(entries);

  final int budgetMinor;

  /// Categories in display order.
  final List<Category> categories;

  /// Entries in the order they were added, oldest first.
  final List<Entry> entries;

  BudgetState copyWith({
    int? budgetMinor,
    List<Category>? categories,
    List<Entry>? entries,
  }) => BudgetState(
    budgetMinor: budgetMinor ?? this.budgetMinor,
    categories: categories ?? this.categories,
    entries: entries ?? this.entries,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BudgetState &&
          other.budgetMinor == budgetMinor &&
          _listEquals(other.categories, categories) &&
          _listEquals(other.entries, entries);

  @override
  int get hashCode => Object.hash(
    budgetMinor,
    Object.hashAll(categories),
    Object.hashAll(entries),
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Holds [BudgetState], seeded at start from the design prototype.
class BudgetNotifier extends Notifier<BudgetState> {
  @override
  BudgetState build() {
    final now = ref.watch(clockProvider)();
    return BudgetState(
      budgetMinor: seedBudgetMinor,
      categories: seedCategories,
      entries: seedEntries(now),
    );
  }

  /// Appends [entry] as it stands.
  void addEntry(Entry entry) {
    state = state.copyWith(entries: [...state.entries, entry]);
  }

  /// Adds an expense dated now (or at [occurredAt]) and returns it, so the
  /// caller can undo it with [removeEntry].
  Entry addExpense({
    required int amountMinor,
    required String categoryId,
    String note = '',
    DateTime? occurredAt,
  }) {
    final entry = Entry(
      id: newEntryId(),
      type: EntryType.expense,
      amountMinor: amountMinor,
      categoryId: categoryId,
      note: note,
      occurredAt: occurredAt ?? ref.read(clockProvider)(),
    );
    addEntry(entry);
    return entry;
  }

  /// Adds income dated now (or at [occurredAt]) and returns it. [note] is
  /// where the income source name goes, for example "Freelance".
  Entry addIncome({
    required int amountMinor,
    String note = '',
    DateTime? occurredAt,
  }) {
    final entry = Entry(
      id: newEntryId(),
      type: EntryType.income,
      amountMinor: amountMinor,
      note: note,
      occurredAt: occurredAt ?? ref.read(clockProvider)(),
    );
    addEntry(entry);
    return entry;
  }

  /// Removes the entry with [id]. Returns false, and changes nothing, when no
  /// entry has that id.
  bool removeEntry(String id) {
    final remaining = [
      for (final e in state.entries)
        if (e.id != id) e,
    ];
    if (remaining.length == state.entries.length) return false;
    state = state.copyWith(entries: remaining);
    return true;
  }
}

/// The budget, categories and entries, with the actions that change them.
final budgetProvider = NotifierProvider<BudgetNotifier, BudgetState>(
  BudgetNotifier.new,
);

/// The figures every screen shows, for the clock's current moment.
///
/// Recomputed whenever the state changes. It does not recompute by itself when
/// the date rolls over; call `ref.invalidate(budgetSnapshotProvider)` for that
/// (for example when the app returns to the foreground).
final budgetSnapshotProvider = Provider<BudgetSnapshot>((ref) {
  final state = ref.watch(budgetProvider);
  final now = ref.watch(clockProvider)();
  return budgetSnapshot(
    budgetMinor: state.budgetMinor,
    entries: state.entries,
    categories: state.categories,
    now: now,
  );
});
