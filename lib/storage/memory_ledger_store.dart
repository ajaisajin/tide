/// A ledger held in memory: for tests, for the web, and for development
/// scenarios. Nothing is saved. Pure Dart.
library;

import '../budget/budget.dart';
import '../log/chips.dart';
import '../state/seed.dart';
import 'ledger_store.dart';

class _Row {
  _Row(this.entry);
  final Entry entry;
  bool deleted = false;
}

/// A [LedgerStore] that keeps everything in memory and forgets it when the
/// app closes. It follows the same rules as the saved store; one shared test
/// suite runs against both.
class MemoryLedgerStore implements LedgerStore {
  /// An empty ledger, or one starting with the data given. A ledger with no
  /// budgets is one where setup has not been completed.
  MemoryLedgerStore({
    Iterable<Entry> entries = const [],
    Iterable<Category> categories = const [],
    Map<YearMonth, int> budgets = const {},
    this._profile,
  }) : _rows = [for (final e in entries) _Row(storedForm(e))],
       _categories = [...categories],
       _budgets = {...budgets};

  /// The sample month: the twelve seed expenses re-dated into the calendar
  /// month of [now] exactly as `seedEntries` does, the six seed categories
  /// with their seed limits, and the seed budget of ₹30,000 set for that
  /// month. No profile unless [profile] is given, because the sample data has
  /// no income figure.
  MemoryLedgerStore.sampleMonth(DateTime now, {Profile? profile})
    : this(
        entries: seedEntries(now),
        categories: seedCategories,
        budgets: {YearMonth.of(now): seedBudgetMinor},
        profile: profile,
      );

  // In insertion order.
  final List<_Row> _rows;
  final List<Category> _categories;
  final Map<YearMonth, int> _budgets;
  Profile? _profile;
  bool _closed = false;

  /// Whether [close] has been called.
  bool get isClosed => _closed;

  void _checkOpen() {
    if (_closed) throw StateError('The ledger store has been closed');
  }

  @override
  Future<List<Entry>> entriesForMonth(YearMonth month) async {
    _checkOpen();
    final bounds = monthUtcBounds(month);
    final found = [
      for (final row in _rows)
        if (!row.deleted && bounds.contains(row.entry.occurredAt)) row.entry,
    ];
    // List.sort is not guaranteed stable, so insertion order is the explicit
    // second key.
    final order = {for (final (i, e) in found.indexed) e.id: i};
    found.sort((a, b) {
      final byTime = a.occurredAt.compareTo(b.occurredAt);
      return byTime != 0 ? byTime : order[a.id]!.compareTo(order[b.id]!);
    });
    return found;
  }

  @override
  Future<Entry> insertEntry(Entry entry) async {
    _checkOpen();
    if (_rows.any((row) => row.entry.id == entry.id)) {
      throw StateError('An entry with id ${entry.id} already exists');
    }
    final stored = storedForm(entry);
    _rows.add(_Row(stored));
    return stored;
  }

  @override
  Future<bool> softDeleteEntry(String id) async {
    _checkOpen();
    for (final row in _rows) {
      if (row.entry.id == id && !row.deleted) {
        row.deleted = true;
        return true;
      }
    }
    return false;
  }

  @override
  Future<List<int>> frequentExpenseAmounts({int limit = 5}) async {
    _checkOpen();
    if (limit <= 0) return [];
    return frequentAmounts([
      for (final row in _rows)
        if (!row.deleted) row.entry,
    ], limit: limit);
  }

  @override
  Future<List<Category>> loadCategories() async {
    _checkOpen();
    return [..._categories];
  }

  @override
  Future<bool> saveCategoryLimit(String categoryId, int limitMinor) async {
    _checkOpen();
    final index = _categories.indexWhere((c) => c.id == categoryId);
    if (index < 0) return false;
    final old = _categories[index];
    _categories[index] = Category(
      id: old.id,
      name: old.name,
      colorValue: old.colorValue,
      limitMinor: limitMinor,
    );
    return true;
  }

  @override
  Future<void> replaceCategories(List<Category> categories) async {
    _checkOpen();
    final ids = {for (final c in categories) c.id};
    if (ids.length != categories.length) {
      throw ArgumentError('Two categories share an id');
    }
    _categories
      ..clear()
      ..addAll(categories);
  }

  @override
  Future<int?> budgetFor(YearMonth month) async {
    _checkOpen();
    return effectiveBudgetMinor(_budgets, month);
  }

  @override
  Future<bool> hasAnyBudget() async {
    _checkOpen();
    return _budgets.isNotEmpty;
  }

  @override
  Future<void> setBudget(YearMonth month, int totalMinor) async {
    _checkOpen();
    _budgets[month] = totalMinor;
  }

  @override
  Future<Profile?> loadProfile() async {
    _checkOpen();
    return _profile;
  }

  @override
  Future<void> saveProfile(Profile profile) async {
    _checkOpen();
    _profile = profile;
  }

  @override
  Future<void> saveBudgetSettings({
    Profile? profile,
    List<Category>? categories,
    Map<String, int> categoryLimits = const {},
    ({YearMonth month, int totalMinor})? budget,
  }) async {
    _checkOpen();
    // Everything that can be refused is checked before anything is changed.
    final next = [...(categories ?? _categories)];
    if ({for (final c in next) c.id}.length != next.length) {
      throw ArgumentError('Two categories share an id');
    }
    for (final MapEntry(key: id, value: limitMinor) in categoryLimits.entries) {
      final index = next.indexWhere((c) => c.id == id);
      if (index < 0) throw StateError('There is no category with id $id');
      final old = next[index];
      next[index] = Category(
        id: old.id,
        name: old.name,
        colorValue: old.colorValue,
        limitMinor: limitMinor,
      );
    }
    _categories
      ..clear()
      ..addAll(next);
    if (profile != null) _profile = profile;
    if (budget != null) _budgets[budget.month] = budget.totalMinor;
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}
