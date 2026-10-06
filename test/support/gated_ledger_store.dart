import 'dart:async';

import 'package:tide/budget/budget.dart';
import 'package:tide/storage/storage.dart';

import 'failing_ledger_store.dart';

/// A [FailingLedgerStore] whose writes of entries and of budget settings can
/// also be held back, so a test can look at the app while a save is in
/// flight.
///
/// After [hold], `insertEntry`, `softDeleteEntry` and `saveBudgetSettings`
/// wait until [release].
/// What happens then follows the failure switches as they stand at release.
class GatedLedgerStore extends FailingLedgerStore {
  GatedLedgerStore({super.inner});

  Completer<void>? _gate;

  /// How many inserts and deletes have been asked for, held or not.
  int inserts = 0;
  int deletes = 0;

  /// How many times budget settings have been asked to be saved.
  int settingsSaves = 0;

  void hold() => _gate ??= Completer<void>();

  void release() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<Entry> insertEntry(Entry entry) async {
    inserts++;
    await _gate?.future;
    return super.insertEntry(entry);
  }

  @override
  Future<bool> softDeleteEntry(String id) async {
    deletes++;
    await _gate?.future;
    return super.softDeleteEntry(id);
  }

  @override
  Future<void> saveBudgetSettings({
    Profile? profile,
    List<Category>? categories,
    Map<String, int> categoryLimits = const {},
    ({YearMonth month, int totalMinor})? budget,
  }) async {
    settingsSaves++;
    await _gate?.future;
    return super.saveBudgetSettings(
      profile: profile,
      categories: categories,
      categoryLimits: categoryLimits,
      budget: budget,
    );
  }
}
