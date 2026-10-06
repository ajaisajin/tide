import 'package:flutter_test/flutter_test.dart';
import 'package:tide/budget/budget.dart';
import 'package:tide/dev/scenario.dart';
import 'package:tide/state/budget_state.dart';
import 'package:tide/state/seed.dart';
import 'package:tide/storage/storage.dart';

import '../support/ledger_container.dart';

void main() {
  final oct5 = DateTime(2026, 10, 5, 10);

  Future<BudgetSnapshot> snapshotOf(String name) async {
    final c = await ledgerContainer(
      now: oct5,
      store: scenarioStore(name, oct5),
    );
    return c.read(budgetSnapshotProvider);
  }

  test('scenarios are off in an ordinary build', () {
    expect(tideScenario, isEmpty);
    expect(scenarioOverrides(), isEmpty);
  });

  test('demo is the old seeded app: ₹30,000 budget, the six categories with '
      'their sample limits, twelve expenses, ₹13,601 remaining', () async {
    final store = scenarioStore('demo', oct5);
    expect(store, isA<MemoryLedgerStore>());
    expect(await store.hasAnyBudget(), isTrue);
    expect(await store.loadCategories(), seedCategories);
    expect(
      await store.entriesForMonth(const YearMonth(2026, 10)),
      seedEntries(oct5),
    );

    final s = await snapshotOf('demo');
    expect(s.budgetMinor, rupees(30000));
    expect(s.remainingMinor, rupees(13601));
    expect(s.fillPercent, 45);
    expect(s.band, StatusBand.runningLower);
    expect(s.safeToSpendTodayMinor, rupees(503));
    expect(s.categoryById('bills')!.limitMinor, rupees(11000));
    expect(s.categoryById('shop')!.limitMinor, rupees(2000));
  });

  test('a name that is not known starts as demo does', () async {
    expect(await snapshotOf('nonsense'), await snapshotOf('demo'));
  });

  test('each named state is the one it says', () async {
    final full = await snapshotOf('full');
    expect(full.remainingMinor, rupees(30000));
    expect(full.fillPercent, 100);

    expect((await snapshotOf('low')).remainingMinor, rupees(600));
    expect((await snapshotOf('low')).band, StatusBand.nearlyDry);

    final calm = await snapshotOf('calm');
    expect(calm.availableMinor, rupees(40000));
    expect(calm.band, StatusBand.calmWater);
    expect(await snapshotOf('cycle'), calm);

    expect((await snapshotOf('coral')).band, StatusBand.nearlyDry);

    final overspent = await snapshotOf('overspent');
    expect(overspent.remainingMinor, rupees(-2000));
    expect(overspent.band, StatusBand.belowTheLine);

    final overlimit = await snapshotOf('overlimit');
    expect(overlimit.categoryById('shop')!.overLimit, isTrue);
  });
}
