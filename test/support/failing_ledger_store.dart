import 'package:tide/budget/budget.dart';
import 'package:tide/storage/storage.dart';

/// What [FailingLedgerStore] throws when told to fail.
class LedgerStoreFailure implements Exception {
  const LedgerStoreFailure(this.operation);

  /// The name of the method that was made to fail.
  final String operation;

  @override
  String toString() => 'LedgerStoreFailure($operation)';
}

/// A store for tests that can be told to fail.
///
/// It passes everything to [inner] (an empty in-memory store unless one is
/// given) until a switch is set. While a switch is on, the matching calls
/// throw a [LedgerStoreFailure] and [inner] is not touched, as with a real
/// write that did not happen. Switches can be flipped at any time.
class FailingLedgerStore implements LedgerStore {
  FailingLedgerStore({
    LedgerStore? inner,
    this.failOnInsert = false,
    this.failOnDelete = false,
    this.failOnSave = false,
  }) : inner = inner ?? MemoryLedgerStore();

  final LedgerStore inner;

  /// Makes [insertEntry] throw.
  bool failOnInsert;

  /// Makes [softDeleteEntry] throw.
  bool failOnDelete;

  /// Makes [saveCategoryLimit], [replaceCategories], [setBudget],
  /// [saveProfile] and [saveBudgetSettings] throw.
  bool failOnSave;

  /// How many calls have been made to fail so far.
  int failures = 0;

  Never _fail(String operation) {
    failures++;
    throw LedgerStoreFailure(operation);
  }

  @override
  Future<Entry> insertEntry(Entry entry) async {
    if (failOnInsert) _fail('insertEntry');
    return inner.insertEntry(entry);
  }

  @override
  Future<bool> softDeleteEntry(String id) async {
    if (failOnDelete) _fail('softDeleteEntry');
    return inner.softDeleteEntry(id);
  }

  @override
  Future<bool> saveCategoryLimit(String categoryId, int limitMinor) async {
    if (failOnSave) _fail('saveCategoryLimit');
    return inner.saveCategoryLimit(categoryId, limitMinor);
  }

  @override
  Future<void> replaceCategories(List<Category> categories) async {
    if (failOnSave) _fail('replaceCategories');
    return inner.replaceCategories(categories);
  }

  @override
  Future<void> setBudget(YearMonth month, int totalMinor) async {
    if (failOnSave) _fail('setBudget');
    return inner.setBudget(month, totalMinor);
  }

  @override
  Future<void> saveProfile(Profile profile) async {
    if (failOnSave) _fail('saveProfile');
    return inner.saveProfile(profile);
  }

  @override
  Future<void> saveBudgetSettings({
    Profile? profile,
    List<Category>? categories,
    Map<String, int> categoryLimits = const {},
    ({YearMonth month, int totalMinor})? budget,
  }) async {
    if (failOnSave) _fail('saveBudgetSettings');
    return inner.saveBudgetSettings(
      profile: profile,
      categories: categories,
      categoryLimits: categoryLimits,
      budget: budget,
    );
  }

  @override
  Future<List<Entry>> entriesForMonth(YearMonth month) =>
      inner.entriesForMonth(month);

  @override
  Future<List<int>> frequentExpenseAmounts({int limit = 5}) =>
      inner.frequentExpenseAmounts(limit: limit);

  @override
  Future<List<Category>> loadCategories() => inner.loadCategories();

  @override
  Future<int?> budgetFor(YearMonth month) => inner.budgetFor(month);

  @override
  Future<bool> hasAnyBudget() => inner.hasAnyBudget();

  @override
  Future<Profile?> loadProfile() => inner.loadProfile();

  @override
  Future<void> close() => inner.close();
}
