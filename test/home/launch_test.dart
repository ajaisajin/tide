import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide/budget/budget.dart';
import 'package:tide/home/home_screen.dart';
import 'package:tide/home/open_error_screen.dart';
import 'package:tide/main.dart';
import 'package:tide/setup/setup_screen.dart';
import 'package:tide/state/budget_state.dart';
import 'package:tide/state/ledger.dart';
import 'package:tide/state/seed.dart';
import 'package:tide/state/start_up.dart';
import 'package:tide/storage/storage.dart';

import '../support/pump_home.dart';

/// A setup screen that counts how often it is built.
class _CountingSetup extends StatelessWidget {
  const _CountingSetup(this.builds);

  final List<int> builds;

  @override
  Widget build(BuildContext context) {
    builds.add(1);
    return const SetupScreen();
  }
}

Future<Started> _started(LedgerStore store, [DateTime? now]) async =>
    Started(store, await loadLedgerStart(store, now ?? oct5));

/// A ledger that is not the sample month: ₹42,000 budget, ₹1,200 on Food.
MemoryLedgerStore _savedLedger() => MemoryLedgerStore(
  entries: [
    Entry(
      id: 'a',
      type: EntryType.expense,
      amountMinor: rupees(1200),
      categoryId: 'food',
      occurredAt: DateTime(2026, 10, 3, 9),
    ),
  ],
  categories: seedCategories,
  budgets: {const YearMonth(2026, 10): rupees(42000)},
  profile: Profile(monthlyIncomeMinor: rupees(60000)),
);

const _cannotOpen = StartFailed(
  LedgerCannotBeOpened(LedgerUnreadableReason.keyMissing),
);

void main() {
  group('first frame', () {
    testWidgets('a pre-loaded store shows its own figures on the first '
        'frame', (tester) async {
      await pumpLauncher(tester, initial: await _started(_savedLedger()));

      // No further pump: this is the first frame.
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('₹40,800'), findsOneWidget);
      expect(find.text('left of ₹42,000'), findsOneWidget);
      expect(find.text('97% full'), findsOneWidget);
      expect(find.text('October'), findsOneWidget);
      expect(find.text('₹1,200'), findsOneWidget);
      // Nothing of the sample month.
      expect(find.text('₹13,601'), findsNothing);
      expect(find.text('left of ₹30,000'), findsNothing);
    });
  });

  group('which screen shows', () {
    testWidgets('a ledger with no budget shows setup, not home', (
      tester,
    ) async {
      await pumpLauncher(tester, initial: await _started(MemoryLedgerStore()));
      await tester.pump();

      expect(find.byType(SetupScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.byType(OpenErrorScreen), findsNothing);
    });

    testWidgets('a ledger with a budget shows home, and the setup screen '
        'is never built', (tester) async {
      final builds = <int>[];
      await pumpLauncher(
        tester,
        initial: await _started(_savedLedger()),
        app: TideApp(home: TideRoot(setup: _CountingSetup(builds))),
      );
      expect(builds, isEmpty, reason: 'first frame');
      expect(find.byType(HomeScreen), findsOneWidget);

      await pumpFor(tester, const Duration(milliseconds: 500));
      expect(builds, isEmpty);
      expect(find.byType(SetupScreen), findsNothing);
    });

    testWidgets('a budget set in an earlier month still means home', (
      tester,
    ) async {
      final store = MemoryLedgerStore.sampleMonth(DateTime(2026, 8, 20));
      await pumpLauncher(tester, initial: await _started(store));

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(SetupScreen), findsNothing);
      expect(find.text('left of ₹30,000'), findsOneWidget);
    });

    testWidgets('completing setup moves from setup to home', (tester) async {
      await pumpLauncher(tester, initial: await _started(MemoryLedgerStore()));
      expect(find.byType(SetupScreen), findsOneWidget);

      await containerOf(tester)
          .read(budgetProvider.notifier)
          .completeSetup(
            incomeMinor: rupees(45000),
            budgetMinor: rupees(30000),
          );
      await tester.pump();

      expect(find.byType(SetupScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('₹30,000'), findsOneWidget);
      expect(find.text('left of ₹30,000'), findsOneWidget);
      expect(find.text('100% full'), findsOneWidget);
    });
  });

  group('saved data that cannot be opened', () {
    testWidgets('says so and offers Retry, with neither setup nor an empty '
        'home', (tester) async {
      await pumpLauncher(tester, initial: _cannotOpen);

      expect(find.byType(OpenErrorScreen), findsOneWidget);
      expect(find.text('Tide’s data could not be opened'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(OpenErrorScreen.retryKey)).height,
        greaterThanOrEqualTo(48),
      );
      expect(find.byType(SetupScreen), findsNothing);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('a failure of another kind shows the same screen', (
      tester,
    ) async {
      await pumpLauncher(
        tester,
        initial: StartFailed(
          LedgerOpenFailed(StateError('no disk'), StackTrace.empty),
        ),
      );
      expect(find.byType(OpenErrorScreen), findsOneWidget);
      expect(find.byType(SetupScreen), findsNothing);
    });

    testWidgets('Retry leads to home with the saved figures once the '
        'store opens', (tester) async {
      var starts = 0;
      final opened = await _started(_savedLedger());
      await pumpLauncher(
        tester,
        initial: _cannotOpen,
        start: () async => ++starts < 2 ? _cannotOpen : opened,
      );

      // Still cannot be opened: the error screen stays.
      await tester.tap(find.byKey(OpenErrorScreen.retryKey));
      await tester.pump();
      expect(starts, 1);
      expect(find.byType(OpenErrorScreen), findsOneWidget);
      expect(find.byType(SetupScreen), findsNothing);
      expect(find.byType(HomeScreen), findsNothing);

      await tester.tap(find.byKey(OpenErrorScreen.retryKey));
      await tester.pump();
      expect(starts, 2);
      expect(find.byType(OpenErrorScreen), findsNothing);
      expect(find.byType(SetupScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('₹40,800'), findsOneWidget);
      expect(find.text('left of ₹42,000'), findsOneWidget);
    });

    testWidgets('Retry answers once while a retry is under way', (
      tester,
    ) async {
      var starts = 0;
      await pumpLauncher(
        tester,
        initial: _cannotOpen,
        start: () async {
          starts++;
          await Future<void>.delayed(const Duration(seconds: 1));
          return _cannotOpen;
        },
      );

      await tester.tap(find.byKey(OpenErrorScreen.retryKey));
      await tester.pump();
      await tester.tap(find.byKey(OpenErrorScreen.retryKey));
      await tester.pump();
      expect(starts, 1);

      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(OpenErrorScreen.retryKey));
      await tester.pump();
      expect(starts, 2);
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
