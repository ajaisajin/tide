import 'package:flutter_test/flutter_test.dart';
import 'package:tide/budget/budget.dart';
import 'package:tide/home/confirmation_toast.dart';
import 'package:tide/log/log_flow.dart';
import 'package:tide/state/confirmation_state.dart';
import 'package:tide/state/ledger.dart';
import 'package:tide/state/timing_state.dart';
import 'package:tide/storage/storage.dart';
import 'package:tide/vessel/vessel_layer.dart';

import '../support/gated_ledger_store.dart';
import '../support/log_helpers.dart';
import '../support/pump_home.dart';

void main() {
  final undo = find.byKey(ConfirmationToast.undoKey);
  final toast = find.byKey(ConfirmationToast.toastKey);

  group('confirmation', () {
    testWidgets('an expense shows "Logged ₹250 to Food" with Undo, on the '
        'home screen', (tester) async {
      final app = await pumpLogApp(tester);
      expect(toast, findsNothing);
      await app.log('250', 'food');
      expect(toast, findsOneWidget);
      expect(find.textContaining('Logged ₹250 to Food'), findsOneWidget);
      expect(undo, findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(tester.getSize(undo).height, greaterThanOrEqualTo(44));
      expect(tester.getRect(toast).bottom, lessThanOrEqualTo(915));
    });

    testWidgets('it sits below the top inset, clear of the figures and the '
        'pebbles', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 48, bottom: 24);
      final app = await pumpLogApp(tester);
      await app.log('250', 'food');
      final rect = tester.getRect(toast);
      expect(rect.top, greaterThanOrEqualTo(48));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(412));
      expect(
        rect.bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(VesselLayer.figuresKey)).top,
        ),
      );
    });

    testWidgets('a tap on the message puts it away and keeps the entry', (
      tester,
    ) async {
      final app = await pumpLogApp(tester);
      final count = app.entries.length;
      await app.log('250', 'food');
      await tester.tapAt(tester.getTopLeft(toast) + const Offset(30, 28));
      await app.settle();
      expect(toast, findsNothing);
      expect(app.entries.length, count + 1);
      // The handle is free again.
      await app.open();
    });

    testWidgets('pulling down opens the log flow while it shows', (
      tester,
    ) async {
      final app = await pumpLogApp(tester);
      await app.log('250', 'food');
      await tester.dragFrom(const Offset(206, 500), const Offset(0, 100));
      await app.settle();
      expect(app.isOpen, isTrue);
    });

    testWidgets('the toast is a live region', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await pumpLogApp(tester);
      await app.log('250', 'food');
      final node = tester.getSemantics(toast);
      expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      expect(node.label, contains('Logged ₹250 to Food'));
      semantics.dispose();
    });

    testWidgets('the undo window is 10 seconds', (tester) async {
      expect(undoWindow, const Duration(seconds: 10));
      await pumpLogApp(tester);
    });
  });

  group('undo', () {
    testWidgets('Undo 4 seconds after filing ₹250 to Food removes the entry '
        'and puts ₹250 back', (tester) async {
      final app = await pumpLogApp(tester);
      final before = app.entries;
      await app.log('250', 'food');
      expect(app.snapshot.remainingMinor, rupees(13351));

      await tester.pump(const Duration(seconds: 4));
      expect(undo, findsOneWidget);
      await app.undo();

      expect(app.entries, before);
      expect(app.snapshot.remainingMinor, rupees(13601));
      expect(find.text('₹13,601'), findsOneWidget);
      expect(undo, findsNothing);
      expect(find.textContaining('Logged'), findsNothing);
    });

    testWidgets('Undo is still there at 9.5 seconds', (tester) async {
      final app = await pumpLogApp(tester);
      await app.log('250', 'food');
      await tester.pump(const Duration(milliseconds: 9100));
      expect(undo, findsOneWidget);
    });

    testWidgets('after 10 seconds the toast and Undo are gone and the entry '
        'stays', (tester) async {
      final app = await pumpLogApp(tester);
      final count = app.entries.length;
      await app.log('250', 'food');
      await tester.pump(const Duration(seconds: 10));
      await app.settle();

      expect(undo, findsNothing);
      expect(toast, findsNothing);
      expect(find.textContaining('Logged'), findsNothing);
      expect(app.entries.length, count + 1);
      expect(app.snapshot.remainingMinor, rupees(13351));
      // Nothing is left to undo.
      containerOf(tester).read(confirmationProvider.notifier).undo();
      expect(app.entries.length, count + 1);
    });

    testWidgets('a second entry replaces the first confirmation, and Undo '
        'then removes the second only', (tester) async {
      final app = await pumpLogApp(tester);
      final count = app.entries.length;
      await app.log('250', 'food');
      final first = app.entries.last;
      await tester.pump(const Duration(seconds: 3));
      await app.log('90', 'travel');
      final second = app.entries.last;

      expect(find.textContaining('Logged ₹250 to Food'), findsNothing);
      expect(find.textContaining('Logged ₹90 to Travel'), findsOneWidget);
      expect(undo, findsOneWidget);

      // The second entry gets its own full ten seconds.
      await tester.pump(const Duration(seconds: 8));
      expect(undo, findsOneWidget);
      await app.undo();

      expect(app.entries.length, count + 1);
      expect(app.entries.contains(first), isTrue);
      expect(app.entries.contains(second), isFalse);
      expect(app.snapshot.remainingMinor, rupees(13601 - 250));
      expect(undo, findsNothing);
    });

    testWidgets('income can be undone too', (tester) async {
      final app = await pumpLogApp(tester);
      await app.open();
      await tester.tap(find.byKey(LogFlow.incomeKey));
      await tester.pump();
      await app.type('5000');
      await app.tapSource('Freelance');
      expect(app.snapshot.availableMinor, rupees(35000));
      await app.undo();
      expect(app.snapshot.availableMinor, rupees(30000));
      expect(app.snapshot.remainingMinor, rupees(13601));
    });

    testWidgets('with reduce-motion on the toast still comes and goes', (
      tester,
    ) async {
      final app = await pumpLogApp(tester, still: true);
      await tester.tap(find.text('Pull down to log'));
      await tester.pump();
      await app.type('250');
      await tester.tap(find.byKey(LogFlow.pebbleKey('food')));
      await tester.pump();
      expect(find.byType(LogFlow), findsNothing);
      expect(undo, findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(undo, findsNothing);
    });
  });

  group('undo and the saved ledger', () {
    const oct = YearMonth(2026, 10);

    Future<(LogHarness, GatedLedgerStore)> pumpGated(
      WidgetTester tester,
    ) async {
      final store = GatedLedgerStore(
        inner: MemoryLedgerStore.sampleMonth(oct5),
      );
      return (await pumpLogApp(tester, store: store), store);
    }

    testWidgets('after Undo the store no longer returns the entry', (
      tester,
    ) async {
      final app = await pumpLogApp(tester);
      await app.log('250', 'food');
      final entry = app.entries.last;
      expect(await app.store.entriesForMonth(oct), contains(entry));

      await app.undo();

      expect(await app.store.entriesForMonth(oct), isNot(contains(entry)));
      expect(await app.store.entriesForMonth(oct), hasLength(12));
      expect(find.text('Entry removed'), findsOneWidget);
      // What a restart would load from the same store.
      final restarted = await loadLedgerStart(app.store, oct5);
      expect(restarted.entries.map((e) => e.id), isNot(contains(entry.id)));
      expect(restarted.frequentAmountsMinor, isNot(contains(rupees(250))));
    });

    testWidgets('the entry goes from the screen only once it is deleted', (
      tester,
    ) async {
      final (app, store) = await pumpGated(tester);
      await app.log('250', 'food');
      final entry = app.entries.last;

      store.hold();
      await tester.tap(undo);
      await tester.pump();
      // A second tap while the first is in flight.
      await tester.tap(undo, warnIfMissed: false);
      await app.settle();
      expect(store.deletes, 1);
      expect(app.entries, contains(entry));
      expect(app.snapshot.remainingMinor, rupees(13351));
      expect(find.text('Entry removed'), findsNothing);

      store.release();
      await app.settle();
      expect(store.deletes, 1);
      expect(app.entries, isNot(contains(entry)));
      expect(app.snapshot.remainingMinor, rupees(13601));
      expect(find.text('Entry removed'), findsOneWidget);
    });

    testWidgets('a delete that fails leaves the entry and says so', (
      tester,
    ) async {
      final (app, store) = await pumpGated(tester);
      await app.log('250', 'food');
      final entry = app.entries.last;

      store.failOnDelete = true;
      await app.undo();

      expect(app.entries, contains(entry));
      expect(await store.entriesForMonth(oct), contains(entry));
      expect(app.snapshot.remainingMinor, rupees(13351));
      expect(find.text('Entry removed'), findsNothing);
      expect(find.text(undoFailedMessage), findsOneWidget);
      expect(
        containerOf(tester).read(timingsProvider).single.entryId,
        entry.id,
      );

      // Undo is still offered, and works once the store does.
      expect(undo, findsOneWidget);
      store.failOnDelete = false;
      await app.undo();
      expect(app.entries, isNot(contains(entry)));
      expect(await store.entriesForMonth(oct), hasLength(12));
      expect(app.snapshot.remainingMinor, rupees(13601));
      expect(find.text('Entry removed'), findsOneWidget);
      expect(containerOf(tester).read(timingsProvider), isEmpty);
    });
  });

  group('time to log', () {
    testWidgets('an expense filed 2.4 seconds after opening shows "2.4 s"', (
      tester,
    ) async {
      final app = await pumpLogApp(tester);
      await app.log('250', 'food', after: const Duration(milliseconds: 2400));
      expect(find.textContaining('2.4 s'), findsOneWidget);
      expect(find.text('Logged ₹250 to Food · 2.4 s'), findsOneWidget);

      final record = containerOf(tester).read(timingsProvider).single;
      expect(record.elapsed, const Duration(milliseconds: 2400));
      expect(record.entryId, app.entries.last.id);
    });

    testWidgets('the time runs from the flow opening by pull-down too', (
      tester,
    ) async {
      final app = await pumpLogApp(tester);
      await tester.dragFrom(const Offset(206, 500), const Offset(0, 100));
      await app.settle();
      await app.type('40');
      app.clock.advance(const Duration(milliseconds: 1730));
      await app.tapPebble('fun');
      expect(find.text('Logged ₹40 to Fun · 1.7 s'), findsOneWidget);
    });

    testWidgets('income shows no time and is not recorded', (tester) async {
      final app = await pumpLogApp(tester);
      await app.open();
      await tester.tap(find.byKey(LogFlow.incomeKey));
      await tester.pump();
      await app.type('800');
      app.clock.advance(const Duration(seconds: 3));
      await app.tapSource('Refund');
      expect(find.text('Added ₹800 from Refund'), findsOneWidget);
      expect(find.textContaining(' s'), findsNothing);
      expect(containerOf(tester).read(timingsProvider), isEmpty);
    });

    testWidgets('an undone expense leaves the summary', (tester) async {
      final app = await pumpLogApp(tester);
      await app.log('250', 'food', after: const Duration(milliseconds: 2100));
      await tester.pump(const Duration(seconds: 11));
      await app.log('60', 'fun', after: const Duration(milliseconds: 5000));
      expect(containerOf(tester).read(timingSummaryProvider).overall.count, 2);

      await app.undo();
      final summary = containerOf(tester).read(timingSummaryProvider);
      expect(summary.overall.count, 1);
      expect(summary.overall.median, const Duration(milliseconds: 2100));
    });
  });
}
