import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../budget/budget.dart';
import '../storage/storage.dart';
import 'clock.dart';
import 'ledger.dart';
import 'seed.dart';
import 'today.dart';

/// What the screens work from: the month on show with its budget and
/// entries, the categories, and the monthly income. Loaded from the saved
/// ledger and kept in step with it; earlier months stay in the ledger.
class BudgetState {
  BudgetState({
    required this.month,
    required this.budgetMinor,
    required List<Category> categories,
    required List<Entry> entries,
    this.incomeMinor,
    this.setupComplete = true,
  }) : categories = List.unmodifiable(categories),
       entries = List.unmodifiable(entries);

  /// The local calendar month [entries] and [budgetMinor] belong to.
  final YearMonth month;

  /// The budget in force for [month], in paise. 0 until one has been set.
  final int budgetMinor;

  /// Categories in display order.
  final List<Category> categories;

  /// The entries of [month], oldest first as loaded, then in the order they
  /// were added.
  final List<Entry> entries;

  /// The monthly income, in paise; null until one has been saved. A
  /// reference figure only: it never adds to the amount available.
  final int? incomeMinor;

  /// True once a budget has been saved for any month. The root widget shows
  /// setup while this is false.
  final bool setupComplete;

  BudgetState copyWith({
    YearMonth? month,
    int? budgetMinor,
    List<Category>? categories,
    List<Entry>? entries,
    int? incomeMinor,
    bool? setupComplete,
  }) => BudgetState(
    month: month ?? this.month,
    budgetMinor: budgetMinor ?? this.budgetMinor,
    categories: categories ?? this.categories,
    entries: entries ?? this.entries,
    incomeMinor: incomeMinor ?? this.incomeMinor,
    setupComplete: setupComplete ?? this.setupComplete,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BudgetState &&
          other.month == month &&
          other.budgetMinor == budgetMinor &&
          other.incomeMinor == incomeMinor &&
          other.setupComplete == setupComplete &&
          _listEquals(other.categories, categories) &&
          _listEquals(other.entries, entries);

  @override
  int get hashCode => Object.hash(
    month,
    budgetMinor,
    incomeMinor,
    setupComplete,
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

/// Holds [BudgetState], built from what `main()` loaded from the ledger.
///
/// Every action writes to the store first and changes the state only once
/// the write has finished. If the store throws, the state is untouched and
/// the error reaches the caller, who tells the user. Amounts are not checked
/// here; callers apply the rules in `budget_rules.dart` first.
class BudgetNotifier extends Notifier<BudgetState> {
  late LedgerStore _store;

  /// The month in [state], or the one being loaded to replace it.
  late YearMonth _wanted;
  Future<void>? _loading;

  @override
  BudgetState build() {
    _store = ref.watch(ledgerStoreProvider);
    final start = ref.watch(ledgerStartProvider);
    _wanted = start.month;
    _loading = null;
    ref.listen(
      todayProvider,
      (_, today) => _followMonth(YearMonth.of(today)),
      fireImmediately: true,
    );
    return BudgetState(
      month: start.month,
      budgetMinor: start.budgetMinor ?? 0,
      categories: start.categories,
      entries: start.entries,
      incomeMinor: start.incomeMinor,
      setupComplete: start.hasBudget,
    );
  }

  /// Moves to [month] if the state is for another one.
  void _followMonth(YearMonth month) {
    if (month == _wanted) return;
    _wanted = month;
    final loading = _loadMonth(month);
    _loading = loading;
    loading.whenComplete(() {
      if (identical(_loading, loading)) _loading = null;
    });
  }

  /// Replaces the month's entries and budget with those of [month]. If the
  /// store cannot be read the state keeps the month it had, and the next
  /// write or change of day tries again.
  Future<void> _loadMonth(YearMonth month) async {
    try {
      final (entries, budget) = await (
        _store.entriesForMonth(month),
        _store.budgetFor(month),
      ).wait;
      if (!ref.mounted || _wanted != month) return;
      state = state.copyWith(
        month: month,
        entries: entries,
        budgetMinor: budget ?? 0,
      );
    } catch (_) {
      if (ref.mounted && _wanted == month) _wanted = state.month;
    }
  }

  /// Completes once the state is for the current month, so that a write
  /// which finished while a month was loading is neither lost nor doubled.
  Future<void> _monthSettled() async {
    _followMonth(YearMonth.of(ref.read(todayProvider)));
    var loading = _loading;
    while (loading != null) {
      await loading;
      loading = identical(_loading, loading) ? null : _loading;
    }
  }

  /// Saves [entry] as it stands and returns it as stored. It joins the state
  /// if it falls in the month on show.
  Future<Entry> addEntry(Entry entry) async {
    final stored = await _store.insertEntry(entry);
    if (!ref.mounted) return stored;
    await _monthSettled();
    if (!ref.mounted) return stored;
    if (YearMonth.of(stored.occurredAt) == state.month &&
        !state.entries.any((e) => e.id == stored.id)) {
      state = state.copyWith(entries: [...state.entries, stored]);
    }
    unawaited(ref.read(frequentAmountsProvider.notifier).refresh());
    return stored;
  }

  /// Saves an expense dated now (or at [occurredAt]) and returns it as
  /// stored, so the caller can undo it with [removeEntry].
  Future<Entry> addExpense({
    required int amountMinor,
    required String categoryId,
    String note = '',
    DateTime? occurredAt,
  }) => addEntry(
    Entry(
      id: newUuidV7(),
      type: EntryType.expense,
      amountMinor: amountMinor,
      categoryId: categoryId,
      note: note,
      occurredAt: occurredAt ?? ref.read(clockProvider)(),
    ),
  );

  /// Saves income dated now (or at [occurredAt]) and returns it as stored.
  /// [note] is where the income source name goes, for example "Freelance".
  Future<Entry> addIncome({
    required int amountMinor,
    String note = '',
    DateTime? occurredAt,
  }) => addEntry(
    Entry(
      id: newUuidV7(),
      type: EntryType.income,
      amountMinor: amountMinor,
      note: note,
      occurredAt: occurredAt ?? ref.read(clockProvider)(),
    ),
  );

  /// Deletes the entry with [id] from the ledger, then from the state.
  /// Returns false, and changes nothing, when the ledger has no such entry.
  Future<bool> removeEntry(String id) async {
    final removed = await _store.softDeleteEntry(id);
    if (!ref.mounted) return removed;
    await _monthSettled();
    if (!ref.mounted) return removed;
    final remaining = [
      for (final e in state.entries)
        if (e.id != id) e,
    ];
    if (remaining.length != state.entries.length) {
      state = state.copyWith(entries: remaining);
    }
    if (removed) {
      unawaited(ref.read(frequentAmountsProvider.notifier).refresh());
    }
    return removed;
  }

  /// Saves the monthly income, in paise.
  Future<void> setIncome(int incomeMinor) async {
    await _store.saveProfile(Profile(monthlyIncomeMinor: incomeMinor));
    if (ref.mounted) state = state.copyWith(incomeMinor: incomeMinor);
  }

  /// Saves the budget of the month on show, in paise. Other months and the
  /// category limits are untouched.
  Future<void> setBudget(int budgetMinor) async {
    final month = state.month;
    await _store.setBudget(month, budgetMinor);
    if (!ref.mounted) return;
    state = state.copyWith(
      budgetMinor: month == state.month ? budgetMinor : null,
      setupComplete: true,
    );
  }

  /// Saves the monthly limit of the category [categoryId], in paise.
  /// Returns false, and changes nothing, when there is no such category.
  Future<bool> setCategoryLimit(String categoryId, int limitMinor) async {
    final saved = await _store.saveCategoryLimit(categoryId, limitMinor);
    if (!saved || !ref.mounted) return saved;
    state = state.copyWith(
      categories: [
        for (final c in state.categories)
          if (c.id == categoryId)
            Category(
              id: c.id,
              name: c.name,
              colorValue: c.colorValue,
              limitMinor: limitMinor,
            )
          else
            c,
      ],
    );
    return true;
  }

  /// Saves any of the income, the budget of the month on show and category
  /// limits (in paise, by category id) as one write: if it fails, none of
  /// them is saved and the state is untouched. What is left out is left as
  /// it is; other months' budgets always are. A limit for a category that
  /// does not exist makes the whole save fail.
  Future<void> saveBudgetSettings({
    int? incomeMinor,
    int? budgetMinor,
    Map<String, int> categoryLimitsMinor = const {},
  }) async {
    final month = state.month;
    await _store.saveBudgetSettings(
      profile: incomeMinor == null
          ? null
          : Profile(monthlyIncomeMinor: incomeMinor),
      categoryLimits: categoryLimitsMinor,
      budget: budgetMinor == null
          ? null
          : (month: month, totalMinor: budgetMinor),
    );
    if (!ref.mounted) return;
    state = state.copyWith(
      incomeMinor: incomeMinor,
      budgetMinor: month == state.month ? budgetMinor : null,
      categories: categoryLimitsMinor.isEmpty
          ? null
          : [
              for (final c in state.categories)
                if (categoryLimitsMinor[c.id] case final limitMinor?)
                  Category(
                    id: c.id,
                    name: c.name,
                    colorValue: c.colorValue,
                    limitMinor: limitMinor,
                  )
                else
                  c,
            ],
      setupComplete: budgetMinor == null ? null : true,
    );
  }

  /// Completes first-run setup: saves the income, the default categories
  /// with their default limits for [budgetMinor], and [budgetMinor] as the
  /// budget of the month on show. They are saved as one write, so if it
  /// fails nothing is saved and the next launch shows setup again.
  Future<void> completeSetup({
    required int incomeMinor,
    required int budgetMinor,
  }) async {
    final limits = defaultCategoryLimits(budgetMinor);
    final categories = [
      for (final c in seedCategories)
        Category(
          id: c.id,
          name: c.name,
          colorValue: c.colorValue,
          limitMinor: limits[c.id] ?? c.limitMinor,
        ),
    ];
    final month = state.month;
    await _store.saveBudgetSettings(
      profile: Profile(monthlyIncomeMinor: incomeMinor),
      categories: categories,
      budget: (month: month, totalMinor: budgetMinor),
    );
    if (!ref.mounted) return;
    state = state.copyWith(
      incomeMinor: incomeMinor,
      categories: categories,
      budgetMinor: month == state.month ? budgetMinor : null,
      setupComplete: true,
    );
  }
}

/// The budget, categories and entries, with the actions that change them.
final budgetProvider = NotifierProvider<BudgetNotifier, BudgetState>(
  BudgetNotifier.new,
);

/// The figures every screen shows, for today's date.
///
/// Recomputed whenever the state changes and whenever [todayProvider] moves
/// to a new day, which is what keeps safe-to-spend right overnight. While a
/// new month's data is still being loaded it stays on the last day of the
/// month the state holds, so the figures always belong together.
final budgetSnapshotProvider = Provider<BudgetSnapshot>((ref) {
  final state = ref.watch(budgetProvider);
  final today = ref.watch(todayProvider);
  final month = state.month;
  return budgetSnapshot(
    budgetMinor: state.budgetMinor,
    entries: state.entries,
    categories: state.categories,
    now: YearMonth.of(today) == month
        ? today
        : DateTime(month.year, month.month + 1, 0),
  );
});
