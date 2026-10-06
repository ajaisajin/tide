/// The saved ledger as the app sees it. Pure Dart: no Flutter, no `dart:io`,
/// so it can be imported on every platform including the web.
library;

import '../budget/budget.dart';

/// The user's own reference figures. One per ledger.
class Profile {
  const Profile({required this.monthlyIncomeMinor, this.homeCurrency = 'INR'});

  /// Monthly income in paise. A reference figure only: it is never an entry
  /// and never adds to the amount available.
  final int monthlyIncomeMinor;

  /// ISO 4217 code of the currency amounts are kept in.
  final String homeCurrency;

  @override
  bool operator ==(Object other) =>
      other is Profile &&
      other.monthlyIncomeMinor == monthlyIncomeMinor &&
      other.homeCurrency == homeCurrency;

  @override
  int get hashCode => Object.hash(monthlyIncomeMinor, homeCurrency);

  @override
  String toString() => 'Profile(income $monthlyIncomeMinor, $homeCurrency)';
}

/// The form in which a store keeps and returns [entry]: the same entry with
/// its moment cut to whole milliseconds and expressed in local time.
///
/// Stores keep instants as UTC milliseconds, so microseconds do not survive
/// and a UTC `DateTime` comes back as the equal local one. Every store
/// applies this on insert, so that what [LedgerStore.insertEntry] returns
/// equals what a later read returns.
Entry storedForm(Entry entry) {
  final stored = DateTime.fromMillisecondsSinceEpoch(
    entry.occurredAt.millisecondsSinceEpoch,
  );
  if (stored == entry.occurredAt) return entry;
  return Entry(
    id: entry.id,
    type: entry.type,
    amountMinor: entry.amountMinor,
    categoryId: entry.categoryId,
    note: entry.note,
    occurredAt: stored,
    source: entry.source,
  );
}

/// Everything the app reads from and writes to the saved ledger.
///
/// Every write has finished, and is durable for stores that save to disk,
/// when its future completes. A write that fails completes with an error and
/// changes nothing. Stores do not check amounts against the budget rules;
/// callers do that first.
abstract interface class LedgerStore {
  /// The entries of the local calendar month [month] that have not been
  /// deleted, oldest first. Entries at the same moment come in the order they
  /// were inserted. Each `occurredAt` is a local `DateTime`.
  Future<List<Entry>> entriesForMonth(YearMonth month);

  /// Saves [entry] and returns it in its [storedForm], which is what later
  /// reads return. Fails if an entry with the same id exists, deleted or not.
  Future<Entry> insertEntry(Entry entry);

  /// Marks the entry [id] as deleted, so reads no longer return it. Returns
  /// whether there was such an entry that was not already deleted.
  Future<bool> softDeleteEntry(String id);

  /// The expense amounts recorded most often, in paise, across every month,
  /// most frequent first. Amounts recorded equally often go by the more
  /// recently used (the later `occurredAt`, then the later inserted). Income
  /// and deleted entries are not counted. At most [limit] amounts.
  ///
  /// This is the rule of `frequentAmounts` in `lib/log/chips.dart`.
  Future<List<int>> frequentExpenseAmounts({int limit = 5});

  /// The categories, in display order.
  Future<List<Category>> loadCategories();

  /// Sets the monthly limit of the category [categoryId], in paise. Returns
  /// whether there was such a category.
  Future<bool> saveCategoryLimit(String categoryId, int limitMinor);

  /// Makes [categories] the full set of categories, in the order given.
  /// A category whose id is already known is updated; one that is left out is
  /// removed from the list, while entries filed to it keep its id. Used to
  /// seed the defaults.
  Future<void> replaceCategories(List<Category> categories);

  /// The budget in force for [month], in paise: that month's own if one was
  /// set, otherwise the one set for the most recent earlier month. Null when
  /// none was set in or before [month].
  Future<int?> budgetFor(YearMonth month);

  /// Whether a budget has been set for any month. False means setup has not
  /// been completed.
  Future<bool> hasAnyBudget();

  /// Sets the budget of [month] alone, in paise. Other months are untouched.
  Future<void> setBudget(YearMonth month, int totalMinor);

  /// The saved profile, or null when none has been saved.
  Future<Profile?> loadProfile();

  /// Saves [profile], replacing any earlier one.
  Future<void> saveProfile(Profile profile);

  /// Saves several budget settings as one write: all of them are saved, or,
  /// if any part fails, none is.
  ///
  /// Each part is optional and does what its own method does: [profile] as
  /// [saveProfile], [categories] as [replaceCategories], [categoryLimits]
  /// (limits in paise by category id, applied after [categories]) as
  /// [saveCategoryLimit], and [budget] (a month and its total in paise) as
  /// [setBudget]. Unlike [saveCategoryLimit], a limit for a category that
  /// does not exist is an error, and so nothing is saved.
  Future<void> saveBudgetSettings({
    Profile? profile,
    List<Category>? categories,
    Map<String, int> categoryLimits = const {},
    ({YearMonth month, int totalMinor})? budget,
  });

  /// Releases the store. It must not be used afterwards.
  Future<void> close();
}
