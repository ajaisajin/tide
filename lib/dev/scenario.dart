import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;

import '../budget/budget.dart';
import '../state/budget_state.dart';

/// DEVELOPMENT AID, not a product feature.
///
/// Starts the app in a chosen state so the Vessel can be checked by eye:
///
///     flutter run --dart-define=TIDE_SCENARIO=overspent
///
/// Names: `full`, `low`, `calm`, `coral`, `overspent`, `overlimit`, and
/// `cycle`, which files and removes entries every few seconds to show the
/// level and colour changing. Empty (the default) is the ordinary seeded app.
const String tideScenario = String.fromEnvironment('TIDE_SCENARIO');

/// The provider overrides for [tideScenario]; none when it is empty.
List<Override> scenarioOverrides() => tideScenario.isEmpty
    ? const []
    : [budgetProvider.overrideWith(_ScenarioBudget.new)];

class _ScenarioBudget extends BudgetNotifier {
  @override
  BudgetState build() {
    final seeded = super.build();
    final now = DateTime.now();
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

    if (tideScenario == 'cycle') {
      // Calm, amber, coral, overspent, then back up the same way.
      final steps = <void Function()>[
        () => addEntry(spend(8000)),
        () => addEntry(spend(9000)),
        () => addEntry(spend(8600)),
        () => removeEntry('scenario-8600'),
        () => removeEntry('scenario-9000'),
        () => removeEntry('scenario-8000'),
      ];
      var i = 0;
      final timer = Timer.periodic(const Duration(seconds: 4), (_) {
        steps[i++ % steps.length]();
      });
      ref.onDispose(timer.cancel);
      return seeded.copyWith(entries: [...seeded.entries, income(10000)]);
    }

    return switch (tideScenario) {
      'full' => seeded.copyWith(entries: const []),
      'low' => seeded.copyWith(entries: [...seeded.entries, spend(13001)]),
      'calm' => seeded.copyWith(entries: [...seeded.entries, income(10000)]),
      'coral' => seeded.copyWith(entries: [...seeded.entries, spend(8000)]),
      'overspent' => seeded.copyWith(
        entries: [...seeded.entries, spend(15601)],
      ),
      'overlimit' => seeded.copyWith(
        entries: [...seeded.entries, spend(400, 'shop')],
      ),
      _ => seeded,
    };
  }
}
