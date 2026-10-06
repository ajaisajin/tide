import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;

import '../budget/budget.dart';
import '../state/budget_state.dart';
import '../state/seed.dart';
import '../storage/storage.dart';

/// DEVELOPMENT AID, not a product feature.
///
/// Starts the app on sample data held in memory, in a chosen state, so the
/// Vessel can be checked by eye:
///
///     flutter run --dart-define=TIDE_SCENARIO=overspent
///
/// Names: `demo`, the sample month as it is (₹30,000 budget, twelve
/// expenses); `full`, `low`, `calm`, `coral`, `overspent`, `overlimit`; and
/// `cycle`, which files and removes entries every few seconds to show the
/// level and colour changing. Empty (the default) is the real app on the
/// saved ledger.
///
/// A scenario build uses a [MemoryLedgerStore] and never opens the saved
/// ledger, so sample data cannot reach a real database.
const String tideScenario = String.fromEnvironment('TIDE_SCENARIO');

/// The in-memory ledger for the scenario [name] at [now]: the sample month,
/// changed as the scenario calls for.
MemoryLedgerStore scenarioStore(String name, DateTime now) {
  Entry spend(int amount, [String? categoryId]) => Entry(
    id: 'scenario-$amount',
    type: EntryType.expense,
    amountMinor: rupees(amount),
    categoryId: categoryId,
    note: 'Scenario',
    occurredAt: now,
  );
  Entry income(int amount) => Entry(
    id: 'scenario-income-$amount',
    type: EntryType.income,
    amountMinor: rupees(amount),
    note: 'Scenario',
    occurredAt: now,
  );
  final seeded = seedEntries(now);
  return MemoryLedgerStore(
    entries: switch (name) {
      'full' => const [],
      'low' => [...seeded, spend(13001)],
      'calm' || 'cycle' => [...seeded, income(10000)],
      'coral' => [...seeded, spend(8000)],
      'overspent' => [...seeded, spend(15601)],
      'overlimit' => [...seeded, spend(400, 'shop')],
      _ => seeded,
    },
    categories: seedCategories,
    budgets: {YearMonth.of(now): seedBudgetMinor},
  );
}

/// Stands in for opening the saved ledger in a scenario build.
Future<OpenLedgerResult> openScenarioLedger() async =>
    LedgerOpened(scenarioStore(tideScenario, DateTime.now()), created: true);

/// The provider overrides for [tideScenario]; none unless it is `cycle`.
List<Override> scenarioOverrides() => tideScenario == 'cycle'
    ? [budgetProvider.overrideWith(_CycleBudget.new)]
    : const [];

/// Files three expenses one after another, then removes them again, for ever.
class _CycleBudget extends BudgetNotifier {
  @override
  BudgetState build() {
    final state = super.build();
    // Calm, amber, coral, overspent, then back up the same way.
    const amounts = [8000, 9000, 8600];
    final filed = <Entry>[];
    var removing = false;
    final timer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (removing) {
        await removeEntry(filed.removeLast().id);
        removing = filed.isNotEmpty;
      } else {
        final entry = Entry(
          id: newUuidV7(),
          type: EntryType.expense,
          amountMinor: rupees(amounts[filed.length]),
          note: 'Scenario',
          occurredAt: DateTime.now(),
        );
        filed.add(await addEntry(entry));
        removing = filed.length == amounts.length;
      }
    });
    ref.onDispose(timer.cancel);
    return state;
  }
}
