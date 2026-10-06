/// The ledger saved in a Drift (SQLite) database.
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../../budget/budget.dart' as budget;
import '../../budget/budget.dart' show Entry, EntrySource, EntryType, YearMonth;
import '../ledger_store.dart' as api;
import 'tide_database.dart';

/// A [api.LedgerStore] over a [TideDatabase].
///
/// Instants are stored as UTC milliseconds and read back as local
/// `DateTime`s. Rows are never removed; deleting sets a flag.
class DriftLedgerStore implements api.LedgerStore {
  /// A store over [database], which it closes when it is closed. [clock]
  /// gives the time written to the `created_at` and `updated_at` columns and
  /// defaults to `DateTime.now`.
  DriftLedgerStore(this.database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// A store over a new, empty, unencrypted in-memory database, for tests on
  /// the development machine.
  DriftLedgerStore.memory({DateTime Function()? clock})
    : this(TideDatabase(NativeDatabase.memory()), clock: clock);

  final TideDatabase database;
  final DateTime Function() _clock;

  int _now() => _clock().millisecondsSinceEpoch;

  @override
  Future<List<Entry>> entriesForMonth(YearMonth month) async {
    final bounds = budget.monthUtcBounds(month);
    final entries = database.entries;
    final rows =
        await (database.select(entries)
              ..where(
                (e) =>
                    e.deleted.equals(false) &
                    e.occurredAt.isBiggerOrEqualValue(bounds.startMillis) &
                    e.occurredAt.isSmallerThanValue(bounds.endMillis),
              )
              ..orderBy([
                (e) => OrderingTerm.asc(e.occurredAt),
                (e) => OrderingTerm.asc(e.rowId),
              ]))
            .get();
    return [for (final row in rows) _entryOf(row)];
  }

  @override
  Future<Entry> insertEntry(Entry entry) async {
    final stored = api.storedForm(entry);
    final now = _now();
    await database
        .into(database.entries)
        .insert(
          EntriesCompanion.insert(
            id: stored.id,
            type: stored.type.name,
            amountMinor: stored.amountMinor,
            categoryId: Value(stored.categoryId),
            note: Value(stored.note),
            occurredAt: stored.occurredAt.millisecondsSinceEpoch,
            source: stored.source.name,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return stored;
  }

  @override
  Future<bool> softDeleteEntry(String id) async {
    final changed =
        await (database.update(
          database.entries,
        )..where((e) => e.id.equals(id) & e.deleted.equals(false))).write(
          EntriesCompanion(
            deleted: const Value(true),
            updatedAt: Value(_now()),
          ),
        );
    return changed > 0;
  }

  @override
  Future<List<int>> frequentExpenseAmounts({int limit = 5}) async {
    if (limit <= 0) return [];
    // The rule of frequentAmounts in lib/log/chips.dart: most used first,
    // then the more recently used, then the later inserted. Row ids rise with
    // each insert because rows are never removed.
    final rows = await database
        .customSelect(
          'SELECT amount_minor FROM entries '
          "WHERE type = 'expense' AND deleted = 0 AND amount_minor > 0 "
          'GROUP BY amount_minor '
          'ORDER BY COUNT(*) DESC, MAX(occurred_at) DESC, MAX(rowid) DESC '
          'LIMIT ?',
          variables: [Variable.withInt(limit)],
          readsFrom: {database.entries},
        )
        .get();
    return [for (final row in rows) row.read<int>('amount_minor')];
  }

  @override
  Future<List<budget.Category>> loadCategories() async {
    final rows =
        await (database.select(database.categories)
              ..where((c) => c.deleted.equals(false))
              ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
            .get();
    return [
      for (final row in rows)
        budget.Category(
          id: row.id,
          name: row.name,
          colorValue: row.color,
          limitMinor: row.monthlyLimitMinor,
        ),
    ];
  }

  @override
  Future<bool> saveCategoryLimit(String categoryId, int limitMinor) =>
      _saveCategoryLimit(categoryId, limitMinor, _now());

  Future<bool> _saveCategoryLimit(
    String categoryId,
    int limitMinor,
    int now,
  ) async {
    final changed =
        await (database.update(database.categories)
              ..where((c) => c.id.equals(categoryId) & c.deleted.equals(false)))
            .write(
              CategoriesCompanion(
                monthlyLimitMinor: Value(limitMinor),
                updatedAt: Value(now),
              ),
            );
    return changed > 0;
  }

  @override
  Future<void> replaceCategories(List<budget.Category> categories) =>
      _replaceCategories(categories, _now());

  Future<void> _replaceCategories(
    List<budget.Category> categories,
    int now,
  ) async {
    final ids = {for (final c in categories) c.id};
    if (ids.length != categories.length) {
      throw ArgumentError('Two categories share an id');
    }
    await database.transaction(() async {
      // Categories left out are flagged, not removed, like entries.
      await (database.update(
        database.categories,
      )..where((c) => c.deleted.equals(false) & c.id.isNotIn(ids))).write(
        CategoriesCompanion(deleted: const Value(true), updatedAt: Value(now)),
      );
      for (final (index, category) in categories.indexed) {
        await database
            .into(database.categories)
            .insert(
              CategoriesCompanion.insert(
                id: category.id,
                name: category.name,
                color: category.colorValue,
                monthlyLimitMinor: category.limitMinor,
                sortOrder: index,
                createdAt: now,
                updatedAt: now,
              ),
              // A known id keeps its created_at.
              onConflict: DoUpdate(
                (_) => CategoriesCompanion(
                  name: Value(category.name),
                  color: Value(category.colorValue),
                  monthlyLimitMinor: Value(category.limitMinor),
                  sortOrder: Value(index),
                  updatedAt: Value(now),
                  deleted: const Value(false),
                ),
              ),
            );
      }
    });
  }

  @override
  Future<int?> budgetFor(YearMonth month) async {
    // `YYYY-MM` sorts as text in calendar order.
    final row =
        await (database.select(database.budgets)
              ..where((b) => b.month.isSmallerOrEqualValue(month.key))
              ..orderBy([(b) => OrderingTerm.desc(b.month)])
              ..limit(1))
            .getSingleOrNull();
    return row?.totalMinor;
  }

  @override
  Future<bool> hasAnyBudget() async {
    final row = await (database.select(
      database.budgets,
    )..limit(1)).getSingleOrNull();
    return row != null;
  }

  @override
  Future<void> setBudget(YearMonth month, int totalMinor) =>
      _setBudget(month, totalMinor, _now());

  Future<void> _setBudget(YearMonth month, int totalMinor, int now) async {
    await database
        .into(database.budgets)
        .insert(
          BudgetsCompanion.insert(
            month: month.key,
            totalMinor: totalMinor,
            createdAt: now,
            updatedAt: now,
          ),
          onConflict: DoUpdate(
            (_) => BudgetsCompanion(
              totalMinor: Value(totalMinor),
              updatedAt: Value(now),
            ),
          ),
        );
  }

  @override
  Future<api.Profile?> loadProfile() async {
    final row = await (database.select(
      database.profiles,
    )..where((p) => p.id.equals(1))).getSingleOrNull();
    if (row == null) return null;
    return api.Profile(
      monthlyIncomeMinor: row.monthlyIncomeMinor,
      homeCurrency: row.homeCurrency,
    );
  }

  @override
  Future<void> saveProfile(api.Profile profile) async {
    await database
        .into(database.profiles)
        .insertOnConflictUpdate(
          ProfilesCompanion.insert(
            id: const Value(1),
            monthlyIncomeMinor: profile.monthlyIncomeMinor,
            homeCurrency: Value(profile.homeCurrency),
          ),
        );
  }

  @override
  Future<void> saveBudgetSettings({
    api.Profile? profile,
    List<budget.Category>? categories,
    Map<String, int> categoryLimits = const {},
    ({YearMonth month, int totalMinor})? budget,
  }) async {
    final now = _now();
    // One transaction: an error in any part rolls back the parts before it.
    await database.transaction(() async {
      if (profile != null) await saveProfile(profile);
      if (categories != null) await _replaceCategories(categories, now);
      for (final MapEntry(key: id, value: limitMinor)
          in categoryLimits.entries) {
        if (!await _saveCategoryLimit(id, limitMinor, now)) {
          throw StateError('There is no category with id $id');
        }
      }
      if (budget != null) {
        await _setBudget(budget.month, budget.totalMinor, now);
      }
    });
  }

  @override
  Future<void> close() => database.close();

  static Entry _entryOf(EntryRow row) => Entry(
    id: row.id,
    type: EntryType.values.byName(row.type),
    amountMinor: row.amountMinor,
    categoryId: row.categoryId,
    note: row.note,
    occurredAt: DateTime.fromMillisecondsSinceEpoch(row.occurredAt),
    source: EntrySource.values.byName(row.source),
  );
}
