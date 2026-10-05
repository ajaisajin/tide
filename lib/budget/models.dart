/// Data types for Tide's budget logic. Pure Dart: imports nothing from Flutter.
library;

/// Whether an entry takes money out or puts money in.
enum EntryType { expense, income }

/// How an entry came to exist. Only [manual] is produced in this version; the
/// field follows the technical specification's `transactions` table.
enum EntrySource { manual }

/// One expense or income record.
///
/// [amountMinor] is a positive number of paise; [type] says which way it
/// counts. [categoryId] is null for income. [note] holds the user's note, or
/// for income the name of the source (for example "Freelance").
class Entry {
  const Entry({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.occurredAt,
    this.categoryId,
    this.note = '',
    this.source = EntrySource.manual,
  }) : assert(amountMinor >= 0, 'amountMinor is a magnitude, never negative');

  final String id;
  final EntryType type;
  final int amountMinor;
  final String? categoryId;
  final String note;
  final DateTime occurredAt;
  final EntrySource source;

  bool get isExpense => type == EntryType.expense;
  bool get isIncome => type == EntryType.income;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Entry &&
          other.id == id &&
          other.type == type &&
          other.amountMinor == amountMinor &&
          other.categoryId == categoryId &&
          other.note == note &&
          other.occurredAt == occurredAt &&
          other.source == source;

  @override
  int get hashCode =>
      Object.hash(id, type, amountMinor, categoryId, note, occurredAt, source);

  @override
  String toString() =>
      'Entry($id, ${type.name}, $amountMinor, $categoryId, "$note", '
      '$occurredAt, ${source.name})';
}

/// A spending category with a monthly limit.
///
/// [colorValue] is a 32-bit ARGB integer (for example `0xFFF2B880`), kept as an
/// int so this library does not depend on Flutter. Build a colour from it with
/// `Color(category.colorValue)`.
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.limitMinor,
  });

  final String id;
  final String name;
  final int colorValue;
  final int limitMinor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Category &&
          other.id == id &&
          other.name == name &&
          other.colorValue == colorValue &&
          other.limitMinor == limitMinor;

  @override
  int get hashCode => Object.hash(id, name, colorValue, limitMinor);

  @override
  String toString() => 'Category($id, $name, limit $limitMinor)';
}

/// The four states a month can be in, each with the mood label shown on the
/// Vessel.
enum StatusBand {
  calmWater('Calm water'),
  runningLower('Running lower'),
  nearlyDry('Nearly dry'),
  belowTheLine('Below the line');

  const StatusBand(this.label);

  /// The mood label, exactly as the budget-status spec words it.
  final String label;
}

/// Amount available and amount remaining for one calendar month.
class MonthlyPosition {
  const MonthlyPosition({
    required this.budgetMinor,
    required this.incomeMinor,
    required this.spentMinor,
  });

  final int budgetMinor;

  /// Total of the month's income entries.
  final int incomeMinor;

  /// Total of the month's expense entries.
  final int spentMinor;

  /// Budget plus the month's income.
  int get availableMinor => budgetMinor + incomeMinor;

  /// Available minus the month's expenses. Negative when overspent.
  int get remainingMinor => availableMinor - spentMinor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MonthlyPosition &&
          other.budgetMinor == budgetMinor &&
          other.incomeMinor == incomeMinor &&
          other.spentMinor == spentMinor;

  @override
  int get hashCode => Object.hash(budgetMinor, incomeMinor, spentMinor);

  @override
  String toString() =>
      'MonthlyPosition(budget $budgetMinor, income $incomeMinor, '
      'spent $spentMinor)';
}

/// Where one category stands against its limit for the month.
class CategoryPosition {
  const CategoryPosition({required this.category, required this.spentMinor});

  final Category category;

  /// Total of the month's expenses filed to this category.
  final int spentMinor;

  int get limitMinor => category.limitMinor;

  /// Spend as a fraction of the limit: 0.39 for 39%. Not capped at 1, so an
  /// overspent category can read 1.4.
  ///
  /// A category with a zero (or negative) limit has no meaningful share. It
  /// reports 0 while nothing is spent and 1 as soon as anything is.
  double get share {
    if (limitMinor <= 0) return spentMinor > 0 ? 1.0 : 0.0;
    return spentMinor / limitMinor;
  }

  /// [share] as a whole percentage, rounded to nearest: 2,330 of 6,000 is 39.
  ///
  /// This is for display only. [nearLimit] and [overLimit] are decided on the
  /// exact amounts, so a category at 99.6% displays 100 and is still "near".
  int get sharePercent => (share * 100).round();

  /// At least 80% and below 100% of the limit.
  bool get nearLimit =>
      limitMinor > 0 &&
      spentMinor * 5 >= limitMinor * 4 &&
      spentMinor < limitMinor;

  /// 100% of the limit or more. With a zero limit, any spend at all is over.
  bool get overLimit =>
      limitMinor > 0 ? spentMinor >= limitMinor : spentMinor > 0;

  /// Limit minus spend. Negative once the limit is passed.
  int get leftMinor => limitMinor - spentMinor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategoryPosition &&
          other.category == category &&
          other.spentMinor == spentMinor;

  @override
  int get hashCode => Object.hash(category, spentMinor);

  @override
  String toString() => 'CategoryPosition(${category.id}, spent $spentMinor)';
}

/// Everything the screens need to show for one month, computed for one moment.
class BudgetSnapshot {
  BudgetSnapshot({
    required this.now,
    required this.position,
    required this.fillLevel,
    required this.band,
    required this.daysLeft,
    required this.safeToSpendTodayMinor,
    required List<CategoryPosition> categories,
  }) : categories = List.unmodifiable(categories);

  /// The moment the snapshot was computed for. Its year and month pick the
  /// calendar month; its day drives [daysLeft].
  final DateTime now;

  final MonthlyPosition position;

  /// Remaining divided by available, between 0 and 1.
  final double fillLevel;

  final StatusBand band;

  /// Days left in the month, counting today.
  final int daysLeft;

  /// Remaining divided by [daysLeft], rounded down to a whole rupee, in paise.
  final int safeToSpendTodayMinor;

  /// One position per category, in the order the categories were given.
  final List<CategoryPosition> categories;

  int get budgetMinor => position.budgetMinor;
  int get incomeMinor => position.incomeMinor;
  int get spentMinor => position.spentMinor;
  int get availableMinor => position.availableMinor;
  int get remainingMinor => position.remainingMinor;

  /// [fillLevel] as a whole percentage, rounded to nearest: 0.4534 is 45.
  int get fillPercent => (fillLevel * 100).round();

  /// The mood label for [band].
  String get moodLabel => band.label;

  bool get isOverspent => remainingMinor < 0;

  /// The position of the category with [id], or null if there is none.
  CategoryPosition? categoryById(String id) {
    for (final c in categories) {
      if (c.category.id == id) return c;
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BudgetSnapshot ||
        other.now != now ||
        other.position != position ||
        other.fillLevel != fillLevel ||
        other.band != band ||
        other.daysLeft != daysLeft ||
        other.safeToSpendTodayMinor != safeToSpendTodayMinor ||
        other.categories.length != categories.length) {
      return false;
    }
    for (var i = 0; i < categories.length; i++) {
      if (other.categories[i] != categories[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    now,
    position,
    fillLevel,
    band,
    daysLeft,
    safeToSpendTodayMinor,
    Object.hashAll(categories),
  );

  @override
  String toString() =>
      'BudgetSnapshot($now, $position, fill $fillLevel, ${band.name}, '
      '$daysLeft days, safe $safeToSpendTodayMinor, $categories)';
}
