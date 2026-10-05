import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide/home/home_screen.dart';
import 'package:tide/home/timings_sheet.dart';
import 'package:tide/log/amount.dart';
import 'package:tide/log/log_flow.dart';
import 'package:tide/log/timing.dart';
import 'package:tide/state/timing_state.dart';

import '../support/log_helpers.dart';
import '../support/pump_home.dart';

void main() {
  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(TimingsButton.buttonKey));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.byType(TimingsSheet), findsOneWidget);
  }

  /// The texts in the row for [name]: name, count, median.
  List<String> row(WidgetTester tester, String name) => [
    for (final t in tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(TimingsSheet.rowKey(name)),
        matching: find.byType(Text),
      ),
    ))
      t.data!,
  ];

  TimingRecord rec(String id, AmountMethod m, int ms) => TimingRecord(
    entryId: id,
    method: m,
    elapsed: Duration(milliseconds: ms),
  );

  testWidgets('the home screen has a small Timings control, at least 44 '
      'across, clear of the handle', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 48, bottom: 24);
    await pumpLogApp(tester);
    expect(find.text('Timings'), findsOneWidget);
    final button = tester.getRect(find.byKey(TimingsButton.buttonKey));
    expect(button.height, greaterThanOrEqualTo(44));
    expect(button.width, greaterThanOrEqualTo(44));
    expect(button.top, greaterThanOrEqualTo(48));
    expect(button.right, lessThanOrEqualTo(412));
  });

  testWidgets('the sheet is marked as a test instrument and lists pad, ring, '
      'chips and overall, all at zero to begin with', (tester) async {
    await pumpLogApp(tester);
    await openSheet(tester);
    expect(find.text('TEST INSTRUMENT'), findsOneWidget);
    expect(find.text('Time to log'), findsOneWidget);
    for (final name in ['Pad', 'Ring', 'Chips', 'Overall']) {
      expect(row(tester, name), [name, '0 entries', '—']);
    }
    expect(find.byKey(TimingsSheet.clearKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('median per method: pad 3 entries 2.6 s, ring 1 entry 4.0 s, '
      'overall 4 entries 3.0 s', (tester) async {
    await pumpLogApp(tester);
    containerOf(tester).read(timingsProvider.notifier)
      ..add(rec('a', AmountMethod.pad, 2100))
      ..add(rec('b', AmountMethod.pad, 2600))
      ..add(rec('c', AmountMethod.pad, 3400))
      ..add(rec('d', AmountMethod.ring, 4000));
    await openSheet(tester);
    expect(row(tester, 'Pad'), ['Pad', '3 entries', '2.6 s']);
    expect(row(tester, 'Ring'), ['Ring', '1 entry', '4.0 s']);
    expect(row(tester, 'Chips'), ['Chips', '0 entries', '—']);
    expect(row(tester, 'Overall'), ['Overall', '4 entries', '3.0 s']);
  });

  testWidgets('expenses logged through the flow show up by method, and '
      'Clear zeroes the counts without removing entries', (tester) async {
    final app = await pumpLogApp(tester);
    final seeded = app.entries.length;
    await app.log('250', 'food', after: const Duration(milliseconds: 2100));
    await app.log('75', 'fun', after: const Duration(milliseconds: 3100));
    await app.open();
    await tester.tap(find.byKey(LogFlow.chipKey(25000)));
    await tester.pump();
    app.clock.advance(const Duration(milliseconds: 1200));
    await app.tapPebble('food');
    // Let the toast go so it is not in the way.
    await tester.pump(const Duration(seconds: 11));
    await app.settle();

    await openSheet(tester);
    expect(row(tester, 'Pad'), ['Pad', '2 entries', '2.6 s']);
    expect(row(tester, 'Ring'), ['Ring', '0 entries', '—']);
    expect(row(tester, 'Chips'), ['Chips', '1 entry', '1.2 s']);
    expect(row(tester, 'Overall'), ['Overall', '3 entries', '2.1 s']);

    await tester.tap(find.byKey(TimingsSheet.clearKey));
    await tester.pump();
    for (final name in ['Pad', 'Ring', 'Chips', 'Overall']) {
      expect(row(tester, name), [name, '0 entries', '—']);
    }
    expect(containerOf(tester).read(timingsProvider), isEmpty);
    expect(app.entries.length, seeded + 3);
    expect(app.snapshot.remainingMinor, (13601 - 250 - 75 - 250) * 100);
  });

  testWidgets('the back button closes the sheet and leaves the home screen', (
    tester,
  ) async {
    await pumpLogApp(tester);
    await openSheet(tester);
    await tester.binding.handlePopRoute();
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.byType(TimingsSheet), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('the sheet fits a small screen at large text', (tester) async {
    await pumpLogApp(tester, size: const Size(360, 640), textScale: 1.5);
    await openSheet(tester);
    expect(tester.takeException(), isNull);
  });
}
