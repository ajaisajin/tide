// On-device measurement of the save time: 2,000 entries loaded into the real
// encrypted ledger, then 20 saves timed one after another.
//
//   flutter test integration_test/save_speed_test.dart -d emulator-5554
//
// It opens the ledger through `openLedger()`, with the real secure storage
// and the real SQLite build, completes setup through the app's own state,
// and times each save from the call the log flow makes when a pebble is
// tapped (`BudgetNotifier.addExpense`) to that call returning, which is when
// the entry is in the database. Lines it prints start with "TIDE_SPEED".
//
// It uses the app's real ledger path and key name, so it refuses to start on
// an install that already holds a ledger, and removes what it made when it
// finishes. (`flutter test` installs its own build of the app and uninstalls
// it afterwards.)
//
// Add --dart-define=TIDE_IT_KEEP_LEDGER=true to leave the ledger and its key
// in place instead. That is how the cold-start measurement gets its 2,000
// entries without any seeding code in the app: build this file as an APK,
// install and start it by hand so that nothing uninstalls it, then install
// the profile build over it. The README has the commands.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tide/budget/budget.dart';
import 'package:tide/state/budget_state.dart';
import 'package:tide/state/ledger.dart';
import 'package:tide/storage/device_ledger.dart';

const _keepLedger = bool.fromEnvironment('TIDE_IT_KEEP_LEDGER');
const _stored = 2000;
const _timed = 20;

/// The target in the ledger-storage spec, in milliseconds.
const _targetMs = 100;

void _say(String message) {
  // ignore: avoid_print
  print('TIDE_SPEED $message');
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('20 saves on a ledger already holding 2,000 entries', (
    tester,
  ) async {
    final path = await defaultLedgerPath();
    final file = File(path);
    expect(
      file.existsSync(),
      isFalse,
      reason:
          'This install already has a ledger. This test only runs on a '
          'clean install, so that it can never touch real data.',
    );
    if (!_keepLedger) {
      addTearDown(() async {
        if (file.parent.existsSync()) file.parent.deleteSync(recursive: true);
        await const PlatformSecretStore().delete(LedgerKeyVault.defaultName);
        _say('cleaned up: ledger directory and key removed');
      });
    }

    final now = DateTime.now();
    final month = YearMonth.of(now);

    // Real time throughout: the saves are real I/O on another isolate.
    await tester.runAsync(() async {
      // --- Setup, as the setup screen does it. ---
      var opened = await openLedger();
      expect(opened, isA<LedgerOpened>(), reason: '$opened');
      var store = (opened as LedgerOpened).store;
      var container = ProviderContainer(
        overrides: ledgerOverrides(store, await loadLedgerStart(store, now)),
      );
      await container
          .read(budgetProvider.notifier)
          .completeSetup(
            incomeMinor: rupees(45000),
            budgetMinor: rupees(30000),
          );
      final categories = container.read(budgetProvider).categories;
      expect(categories, hasLength(6));

      // --- 2,000 entries: 100 this month, the rest over the 19 before. ---
      final loading = Stopwatch()..start();
      var earlier = month;
      for (var m = 0; m < 20; m++) {
        final perMonth = _stored ~/ 20;
        for (var i = 0; i < perMonth; i++) {
          // This month's are dated in its first minutes, so none of them
          // is in the future or in another month.
          final at = m == 0
              ? DateTime(month.year, month.month, 1, 0, 0, i)
              : DateTime(earlier.year, earlier.month, 1 + i % 28, 8 + i % 12);
          final income = i % 25 == 24;
          await store.insertEntry(
            Entry(
              id: newUuidV7(),
              type: income ? EntryType.income : EntryType.expense,
              amountMinor: rupees(m == 0 ? 10 + i % 7 : 40 + (i * 37) % 900),
              categoryId: income ? null : categories[i % 6].id,
              note: income ? 'Freelance' : categories[i % 6].name,
              occurredAt: at,
            ),
          );
        }
        earlier = earlier.previous;
      }
      loading.stop();
      _say('loaded $_stored entries in ${loading.elapsedMilliseconds} ms');
      container.dispose();
      await store.close();

      // --- Reopen, as a later launch would, and time the saves. ---
      final opening = Stopwatch()..start();
      opened = await openLedger();
      expect(opened, isA<LedgerOpened>(), reason: '$opened');
      store = (opened as LedgerOpened).store;
      final start = await loadLedgerStart(store, DateTime.now());
      opening.stop();
      _say(
        'reopened and read the starting data in '
        '${opening.elapsedMilliseconds} ms '
        '(${start.entries.length} entries this month)',
      );
      expect(start.entries, hasLength(_stored ~/ 20));
      expect(start.hasBudget, isTrue);
      container = ProviderContainer(overrides: ledgerOverrides(store, start));
      final budget = container.read(budgetProvider.notifier);

      final times = <double>[];
      for (var i = 0; i < _timed; i++) {
        final watch = Stopwatch()..start();
        await budget.addExpense(
          amountMinor: rupees(250 + i),
          categoryId: categories[i % 6].id,
          note: categories[i % 6].name,
        );
        watch.stop();
        times.add(watch.elapsedMicroseconds / 1000);
      }
      final median = _median(times);
      final sorted = [...times]..sort();
      _say('saves (ms): ${times.map((t) => t.toStringAsFixed(1)).join(' ')}');
      _say(
        'median=${median.toStringAsFixed(1)} ms '
        'fastest=${sorted.first.toStringAsFixed(1)} ms '
        'slowest=${sorted.last.toStringAsFixed(1)} ms '
        'target=$_targetMs ms entries_before=$_stored saves=$_timed',
      );
      expect(
        container.read(budgetProvider).entries,
        hasLength(_stored ~/ 20 + _timed),
      );

      // Every one of them is in the database.
      container.dispose();
      await store.close();
      opened = await openLedger();
      store = (opened as LedgerOpened).store;
      expect(
        await store.entriesForMonth(month),
        hasLength(_stored ~/ 20 + _timed),
      );
      await store.close();
      if (_keepLedger) _say('KEPT: the ledger and its key are left in place');

      expect(median, lessThanOrEqualTo(_targetMs));
    });
  });
}
