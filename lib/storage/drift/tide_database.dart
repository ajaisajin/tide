/// The saved ledger's tables, schema version 1.
///
/// After changing anything here, regenerate `tide_database.g.dart` with
/// `dart run build_runner build` and export the schema with
/// `dart run drift_dev make-migrations` (see README, "Storage").
library;

import 'package:drift/drift.dart';

part 'tide_database.g.dart';

/// One expense or income record. Rows are never removed: Undo sets
/// [deleted].
@DataClassName('EntryRow')
@TableIndex(name: 'entries_occurred_at', columns: {#occurredAt})
@TableIndex(name: 'entries_category_id', columns: {#categoryId})
class Entries extends Table {
  /// UUID v7, made on the device.
  TextColumn get id => text()();

  /// `expense` or `income`.
  TextColumn get type => text()();

  /// A positive number of paise.
  IntColumn get amountMinor => integer()();
  TextColumn get currency => text().withDefault(const Constant('INR'))();
  TextColumn get categoryId => text().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();

  /// The moment the entry is for, UTC milliseconds since the Unix epoch.
  IntColumn get occurredAt => integer()();

  /// How the entry came to exist, for example `manual`.
  TextColumn get source => text()();

  /// UTC milliseconds since the Unix epoch.
  IntColumn get createdAt => integer()();

  /// UTC milliseconds since the Unix epoch.
  IntColumn get updatedAt => integer()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A spending category with its monthly limit.
@DataClassName('CategoryRow')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// 32-bit ARGB colour.
  IntColumn get color => integer()();

  /// Paise.
  IntColumn get monthlyLimitMinor => integer()();

  /// Position in the display order, from 0.
  IntColumn get sortOrder => integer()();

  /// UTC milliseconds since the Unix epoch.
  IntColumn get createdAt => integer()();

  /// UTC milliseconds since the Unix epoch.
  IntColumn get updatedAt => integer()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The budget set for one calendar month. A month with no row uses the row
/// of the most recent earlier month.
@DataClassName('BudgetRow')
class Budgets extends Table {
  /// `YYYY-MM`, the local calendar month.
  TextColumn get month => text()();

  /// Paise.
  IntColumn get totalMinor => integer()();

  /// UTC milliseconds since the Unix epoch.
  IntColumn get createdAt => integer()();

  /// UTC milliseconds since the Unix epoch.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {month};
}

/// The user's reference figures. At most one row, with [id] 1.
@DataClassName('ProfileRow')
class Profiles extends Table {
  /// Always 1; the check keeps the table to a single row.
  // ignore: recursive_getters, Drift reads this as a column reference
  IntColumn get id => integer().check(id.equals(1))();

  /// Paise.
  IntColumn get monthlyIncomeMinor => integer()();
  TextColumn get homeCurrency => text().withDefault(const Constant('INR'))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'profile';
}

@DriftDatabase(tables: [Entries, Categories, Budgets, Profiles])
class TideDatabase extends _$TideDatabase {
  TideDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}
