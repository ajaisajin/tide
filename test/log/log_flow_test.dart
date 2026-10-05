import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide/budget/budget.dart';
import 'package:tide/log/amount.dart';
import 'package:tide/log/amount_ring.dart';
import 'package:tide/log/log_flow.dart';
import 'package:tide/log/number_pad.dart';
import 'package:tide/log/ring_tracker.dart';
import 'package:tide/state/log_session_state.dart';
import 'package:tide/state/seed.dart';
import 'package:tide/state/timing_state.dart';
import 'package:tide/theme/tide_theme.dart';

import '../support/log_helpers.dart';
import '../support/pump_home.dart';

void main() {
  Future<void> showRing(WidgetTester tester) async {
    await tester.tap(find.byKey(LogFlow.ringSwitchKey));
    await tester.pump();
    expect(find.byType(AmountRing), findsOneWidget);
  }

  double maxScroll(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(LogFlow.scrollKey),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position
      .maxScrollExtent;

  group('shell', () {
    testWidgets('opens with the Spend and Income switch, Cancel, ₹0, chips, '
        'the pad and six pebbles', (tester) async {
      final app = await pumpLogApp(tester);
      await app.open();

      expect(find.text('Spend'), findsOneWidget);
      expect(find.text('Income'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(app.amountText, '₹0');
      expect(find.byType(NumberPad), findsOneWidget);
      expect(find.byType(AmountRing), findsNothing);
      expect(find.text('Add note'), findsOneWidget);
      expect(find.byKey(LogFlow.noteFieldKey), findsNothing);
      for (final c in seedCategories) {
        expect(find.byKey(LogFlow.pebbleKey(c.id)), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(LogFlow),
            matching: find.text(c.name),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('the amount is the largest text, in the display face', (
      tester,
    ) async {
      final app = await pumpLogApp(tester);
      await app.open();
      final amount = tester.widget<Text>(find.byKey(LogFlow.amountKey));
      expect(amount.style!.fontFamily, TideText.displayFamily);
      expect(amount.style!.fontSize, greaterThanOrEqualTo(48));
    });

    testWidgets('the amount stays on show in both Ring and Pad, and in '
        'income mode', (tester) async {
      final app = await pumpLogApp(tester);
      await app.open();
      await app.type('420');
      expect(app.amountText, '₹420');
      await showRing(tester);
      expect(app.amountText, '₹420');
      await tester.tap(find.byKey(LogFlow.incomeKey));
      await tester.pump();
      expect(app.amountText, '₹420');
    });
  });

  group('number pad', () {
    testWidgets('has the digits 0 to 9 and delete, as large keys', (
      tester,
    ) async {
      final app = await pumpLogApp(tester);
      await app.open();
      for (var d = 0; d <= 9; d++) {
        final size = tester.getSize(find.byKey(NumberPad.digitKey(d)));
        expect(size.height, greaterThanOrEqualTo(48), reason: 'key $d');
        expect(size.width, greaterThanOrEqualTo(48), reason: 'key $d');
      }
      expect(
        tester.getSize(find.byKey(NumberPad.deleteKey)).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('pressing 3 then 7 shows ₹37', (tester) async {
      final app = await pumpLogApp(tester);
      await app.open();
      await app.type('3');
      expect(app.amountText, '₹3');
      await app.type('7');
      expect(app.amountText, '₹37');
    });

    testWidgets('delete on ₹1,850 shows ₹185', (tester) async {
      final app = await pumpLogApp(tester);
      await app.open();
      await app.type('1850');
      expect(app.amountText, '₹1,850');
      await tester.tap(find.byKey(NumberPad.deleteKey));
      await tester.pump();
      expect(app.amountText, '₹185');
    });

    testWidgets('digits past ₹9,99,999 are ignored', (tester) async {
      final app = await pumpLogApp(tester);
      await app.open();
      await app.type('9999999');
      expect(app.amountText, '₹9,99,999');
    });

    testWidgets('the first digit after a chip replaces the amount', (
      tester,
    ) async {
      final app = await pumpLogApp(tester);
      await app.open();
      await tester.tap(find.byKey(LogFlow.chipKey(rupees(650))));
      await tester.pump();
      expect(app.amountText, '₹650');
      await app.type('37');
      expect(app.amountText, '₹37');
    });
  });

  group('amount ring', () {
    testWidgets('a slow clockwise turn raises the amount by ₹10 a step with '
        'exactly one tick per step', (tester) async {
      final app = await pumpLogApp(tester);
      await app.open();
      await showRing(tester);

      await app.turnRing(math.pi / 2 + 0.05, speed: 1.2);
      expect(app.amountText, '₹60');
      expect(app.haptics.calls, List.filled(6, 'tick'));
    });

    testWidgets('a medium turn steps by ₹100 and a fast spin by ₹1,000, each '
        'with one tick per step', (tester) async {
      final app = await pumpLogApp(tester);
      await app.open();
      await showRing(tester);

      await app.turnRing(math.pi / 2 + 0.05, speed: 4);
      expect(app.amountText, '₹600');
      expect(app.haptics.count('tick'), 6);

      app.haptics.calls.clear();
      await app.turnRing(math.pi / 2 + 0.05, speed: 9);
      expect(app.amountText, '₹6,000');
      expect(app.haptics.count('tick'), 6);
    });

    testWidgets('a fast spin moves the amount further than a slow turn of '
        'the same angle', (tester) async {
      final app = await pumpLogApp(tester);
      await app.open();
      await showRing(tester);
      await app.turnRing(math.pi, speed: 1.2);
      final slow = int.parse(app.amountText.replaceAll(RegExp('[₹,]'), ''));
      await tester.tap(find.byKey(LogFlow.cancelKey));
      await app.settle();

      await app.open();
      await app.turnRing(math.pi, speed: 9);
      final fast = int.parse(app.amountText.replaceAll(RegExp('[₹,]'), ''));
      expect(fast, greaterThan(slow));
    });

    testWidgets('turning anticlockwise lowers the amount, and not below ₹0', (
      tester,
    ) async {
      final app = await pumpLogApp(tester);
      await app.open();
      await app.type('100');
      await showRing(tester);

      await app.turnRing(-(math.pi / 4 + 0.05), speed: 1.2);
      expect(app.amountText, '₹70');
      expect(app.haptics.count('tick'), 3);

      // A full turn back would take off ₹240: it stops at ₹0, and the steps
      // that could not move the amount do not tick.
      app.haptics.calls.clear();
      await app.turnRing(-2 * math.pi, speed: 1.2);
      expect(app.amountText, '₹0');
      expect(app.haptics.count('tick'), 7);
    });

    testWidgets('it cannot pass ₹9,99,999', (tester) async {
      final app = await pumpLogApp(tester);
      await app.open();
      await app.type('999000');
      await showRing(tester);
      await app.turnRing(math.pi, speed: 9);
      expect(app.amountText, '₹9,99,999');
    });

    testWidgets('a touch in the middle of the ring does nothing', (
      tester,
    ) async {
      final app = await pumpLogApp(tester);
      await app.open();
      await showRing(tester);
      final centre = tester.getCenter(find.byType(AmountRing));
      await tester.dragFrom(centre, const Offset(10, 10));
      await tester.pump();
      expect(app.amountText, '₹0');
      expect(app.haptics.calls, isEmpty);
    });

    testWidgets('a screen reader can step it up and down', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await pumpLogApp(tester);
      await app.open();
      await showRing(tester);
      final id = tester
          .getSemantics(find.bySemanticsLabel(RegExp('Amount ring')))
          .id;
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.increase,
          nodeId: id,
          viewId: tester.view.viewId,
        ),
      );
      await tester.pump();
      expect(app.amountText, '₹${RingTracker.slowStepRupees}');
      semantics.dispose();
    });
  });

  group('Ring and Pad switch', () {
    testWidgets('defaults to Pad and swaps the shared area', (tester) async {
      final app = await pumpLogApp(tester);
      await app.open();
      final pad = tester.getRect(find.byType(NumberPad));
      await showRing(tester);
      expect(find.byType(NumberPad), findsNothing);
      final ring = tester.getRect(find.byType(AmountRing));
      expect(ring.top, pad.top);
      expect(ring.bottom, pad.bottom);
      await tester.tap(find.byKey(LogFlow.padSwitchKey));
      await tester.pump();
      expect(find.byType(NumberPad), findsOneWidget);
    });

    testWidgets('reopening shows the one used last time', (tester) async {
      final app = await pumpLogApp(tester);
      await app.open();
      await showRing(tester);
      await tester.tap(find.byKey(LogFlow.cancelKey));
      await app.settle();

      await app.open();
      expect(find.byType(AmountRing), findsOneWidget);
      expect(find.byType(NumberPad), findsNothing);
      expect(containerOf(tester).read(entryPanelProvider), EntryPanel.ring);

      // And after filing with the pad, the pad again.
      await tester.tap(find.byKey(LogFlow.padSwitchKey));
      await tester.pump();
      await app.type('20');
      await app.tapPebble('food');
      await app.open();
      expect(find.byType(NumberPad), findsOneWidget);
    });
  });

  group('chips', () {
    testWidgets('show the five most frequent expense amounts, most recent '
        'first on ties, in Ring and Pad alike', (tester) async {
      final app = await pumpLogApp(tester);
      await app.open();
      final keys = [
        for (final a in [650, 180, 450, 920, 280]) LogFlow.chipKey(rupees(a)),
      ];
      var last = double.negativeInfinity;
      for (final k in keys) {
        expect(find.byKey(k), findsOneWidget);
        final left = tester.getTopLeft(find.byKey(k)).dx;
        expect(left, greaterThan(last));
        last = left;
      }
      expect(find.byKey(LogFlow.chipKey(rupees(8000))), findsNothing);
      await showRing(tester);
      expect(find.byKey(keys.first), findsOneWidget);
    });

    testWidgets('tapping the ₹250 chip sets the amount to ₹250', (
      tester,
    ) async {
      final app = await pumpLogApp(tester);
      app.budget
        ..addExpense(amountMinor: rupees(250), categoryId: 'food')
        ..addExpense(amountMinor: rupees(250), categoryId: 'food');
      await tester.pump();
      await app.open();
      await app.type('9');

      final chip = find.byKey(LogFlow.chipKey(rupees(250)));
      expect(
        find.descendant(of: chip, matching: find.text('₹250')),
        findsOneWidget,
      );
      await tester.tap(chip);
      await tester.pump();
      expect(app.amountText, '₹250');
    });

    testWidgets('a new habit: ₹20 logged most often is the first chip next '
        'time', (tester) async {
      final app = await pumpLogApp(tester);
      await app.log('20', 'food');
      await app.log('20', 'travel');
      await app.open();
      final first = tester.getTopLeft(find.byKey(LogFlow.chipKey(rupees(20))));
      for (final a in [650, 180, 450, 920]) {
        expect(
          tester.getTopLeft(find.byKey(LogFlow.chipKey(rupees(a)))).dx,
          greaterThan(first.dx),
        );
      }
      // Still five at most: the oldest of the once-used amounts dropped off.
      expect(find.byKey(LogFlow.chipKey(rupees(280))), findsNothing);
    });

    testWidgets('chips are at least 44 tall', (tester) async {
      final app = await pumpLogApp(tester);
      await app.open();
      expect(
        tester.getSize(find.byKey(LogFlow.chipKey(rupees(650)))).height,
        greaterThanOrEqualTo(44),
      );
    });
  });

  group('filing an expense', () {
    testWidgets('one tap on Food at ₹250 records it, returns to the Vessel '
        'with ₹250 less and says "Logged ₹250 to Food"', (tester) async {
      final app = await pumpLogApp(tester);
      final before = app.entries.length;
      await app.open();
      await app.type('250');
      app.clock.advance(const Duration(seconds: 2));
      await app.tapPebble('food');

      expect(app.isOpen, isFalse);
      expect(find.byType(LogFlow), findsNothing);
      expect(app.entries.length, before + 1);
      final entry = app.entries.last;
      expect(entry.type, EntryType.expense);
      expect(entry.amountMinor, rupees(250));
      expect(entry.categoryId, 'food');
      expect(entry.occurredAt, app.clock.now);
      expect(entry.note, 'Food');
      expect(app.snapshot.remainingMinor, rupees(13601 - 250));
      expect(find.text('₹13,351'), findsOneWidget);
      expect(find.textContaining('Logged ₹250 to Food'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
    });

    testWidgets('pebbles are equal-sized, in a fixed 3 by 2 grid in category '
        'order, outlined in the category colour', (tester) async {
      final app = await pumpLogApp(tester);
      await app.open();
      final rects = [
        for (final c in seedCategories)
          tester.getRect(find.byKey(LogFlow.pebbleKey(c.id))),
      ];
      for (final r in rects) {
        expect(r.size, rects.first.size);
        expect(r.height, greaterThanOrEqualTo(44));
      }
      for (var i = 0; i < 3; i++) {
        expect(rects[i].top, rects[0].top);
        expect(rects[i + 3].top, rects[3].top);
        expect(rects[i + 3].left, rects[i].left);
      }
      expect(rects[1].left, greaterThan(rects[0].right));
      expect(rects[2].left, greaterThan(rects[1].right));
      expect(rects[3].top, greaterThan(rects[0].bottom));

      for (final c in seedCategories) {
        final material = tester.widget<Material>(
          find.descendant(
            of: find.byKey(LogFlow.pebbleKey(c.id)),
            matching: find.byType(Material),
          ),
        );
        final shape = material.shape! as RoundedRectangleBorder;
        expect(shape.side.color, Color(c.colorValue));
      }
    });

    testWidgets('pebbles are in the same place and the same size on another '
        'day with different spending, and in Ring mode', (tester) async {
      final app = await pumpLogApp(tester);
      Map<String, Rect> rects() => {
        for (final c in seedCategories)
          c.id: tester.getRect(find.byKey(LogFlow.pebbleKey(c.id))),
      };
      await app.open();
      final first = rects();
      await tester.tap(find.byKey(LogFlow.cancelKey));
      await app.settle();

      app.clock.advance(const Duration(days: 9));
      app.budget
        ..addExpense(amountMinor: rupees(4200), categoryId: 'health')
        ..addExpense(amountMinor: rupees(2500), categoryId: 'shop')
        ..addExpense(amountMinor: rupees(90), categoryId: 'fun');
      await tester.pump();

      await app.open();
      expect(rects(), first);
      await showRing(tester);
      expect(rects(), first);
    });

    testWidgets('at ₹0 nothing is recorded, the flow stays open and it says '
        '"Set an amount first"', (tester) async {
      final app = await pumpLogApp(tester);
      final before = app.entries.length;
      await app.open();
      expect(find.text('Set an amount first'), findsNothing);
      await app.tapPebble('food');

      expect(app.isOpen, isTrue);
      expect(find.byType(LogFlow), findsOneWidget);
      expect(app.entries.length, before);
      expect(find.text('Set an amount first'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('confirmation-toast')),
        findsNothing,
      );
      expect(containerOf(tester).read(timingsProvider), isEmpty);

      // The message goes once an amount is set, and filing then works.
      await app.type('5');
      expect(find.text('Set an amount first'), findsNothing);
      await app.tapPebble('food');
      expect(app.entries.length, before + 1);
    });

    testWidgets('typing 0 is still no amount', (tester) async {
      final app = await pumpLogApp(tester);
      final before = app.entries.length;
      await app.open();
      await app.type('0');
      await app.tapPebble('bills');
      expect(app.entries.length, before);
      expect(find.text('Set an amount first'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Set an amount first'), findsNothing);
    });

    testWidgets('each pebble files to its own category', (tester) async {
      final app = await pumpLogApp(tester);
      for (final c in seedCategories) {
        await app.log('15', c.id);
        expect(app.entries.last.categoryId, c.id);
        expect(find.textContaining('Logged ₹15 to ${c.name}'), findsOneWidget);
      }
    });
  });

  group('note', () {
    testWidgets('a typed note is stored on the entry', (tester) async {
      final app = await pumpLogApp(tester);
      await app.open();
      await tester.tap(find.byKey(LogFlow.addNoteKey));
      await tester.pump();
      final field = tester.widget<TextField>(find.byKey(LogFlow.noteFieldKey));
      expect(field.maxLines, 1);
      await tester.enterText(
        find.byKey(LogFlow.noteFieldKey),
        'Lunch with the team',
      );
      await app.type('340');
      await app.tapPebble('food');
      expect(app.entries.last.note, 'Lunch with the team');
      expect(app.entries.last.amountMinor, rupees(340));
    });

    testWidgets('no note stores the category name', (tester) async {
      final app = await pumpLogApp(tester);
      await app.log('340', 'food');
      expect(app.entries.last.note, 'Food');
    });

    testWidgets('a note of spaces only counts as empty', (tester) async {
      final app = await pumpLogApp(tester);
      await app.open();
      await tester.tap(find.byKey(LogFlow.addNoteKey));
      await tester.pump();
      await tester.enterText(find.byKey(LogFlow.noteFieldKey), '   ');
      await app.type('60');
      await app.tapPebble('travel');
      expect(app.entries.last.note, 'Travel');
    });
  });

  group('income', () {
    testWidgets('income mode shows the six sources in place of the pebbles', (
      tester,
    ) async {
      final app = await pumpLogApp(tester);
      await app.open();
      final pebble = tester.getRect(find.byKey(LogFlow.pebbleKey('food')));
      await tester.tap(find.byKey(LogFlow.incomeKey));
      await tester.pump();
      expect(find.byKey(LogFlow.pebbleKey('food')), findsNothing);
      for (final s in incomeSources) {
        expect(find.byKey(LogFlow.sourceKey(s)), findsOneWidget);
        expect(find.text(s), findsOneWidget);
      }
      expect(tester.getRect(find.byKey(LogFlow.sourceKey('Salary'))), pebble);
    });

    testWidgets('₹5,000 from Freelance raises available and remaining by '
        '₹5,000 and says so', (tester) async {
      final app = await pumpLogApp(tester);
      final before = app.snapshot;
      await app.open();
      await tester.tap(find.byKey(LogFlow.incomeKey));
      await tester.pump();
      await app.type('5000');
      await app.tapSource('Freelance');

      expect(app.isOpen, isFalse);
      final entry = app.entries.last;
      expect(entry.type, EntryType.income);
      expect(entry.amountMinor, rupees(5000));
      expect(entry.note, 'Freelance');
      expect(entry.categoryId, isNull);
      expect(app.snapshot.availableMinor, before.availableMinor + rupees(5000));
      expect(app.snapshot.remainingMinor, before.remainingMinor + rupees(5000));
      expect(find.text('₹18,601'), findsOneWidget);
      expect(find.text('left of ₹35,000'), findsOneWidget);
      expect(find.text('Added ₹5,000 from Freelance'), findsOneWidget);
      expect(app.haptics.calls, ['success']);
      // Income is not timed.
      expect(containerOf(tester).read(timingsProvider), isEmpty);
    });

    testWidgets('a source tapped at ₹0 is refused', (tester) async {
      final app = await pumpLogApp(tester);
      final before = app.entries.length;
      await app.open();
      await tester.tap(find.byKey(LogFlow.incomeKey));
      await tester.pump();
      await app.tapSource('Gift');
      expect(app.isOpen, isTrue);
      expect(app.entries.length, before);
      expect(find.text('Set an amount first'), findsOneWidget);
      expect(app.haptics.calls, ['refused']);
    });

    testWidgets('a typed note replaces the source name', (tester) async {
      final app = await pumpLogApp(tester);
      await app.open();
      await tester.tap(find.byKey(LogFlow.incomeKey));
      await tester.pump();
      await tester.tap(find.byKey(LogFlow.addNoteKey));
      await tester.pump();
      await tester.enterText(find.byKey(LogFlow.noteFieldKey), 'Logo job');
      await app.type('1200');
      await app.tapSource('Freelance');
      expect(app.entries.last.note, 'Logo job');
    });
  });

  group('haptics on filing', () {
    testWidgets('a success pulse when an expense is recorded', (tester) async {
      final app = await pumpLogApp(tester);
      await app.log('250', 'food');
      expect(app.haptics.calls, ['success']);
    });

    testWidgets('a different pulse when filing is refused', (tester) async {
      final app = await pumpLogApp(tester);
      await app.open();
      await app.tapPebble('food');
      expect(app.haptics.calls, ['refused']);
    });
  });

  group('last-used method', () {
    Future<AmountMethod> methodAfter(
      WidgetTester tester,
      Future<void> Function(LogHarness app) set,
    ) async {
      final app = await pumpLogApp(tester);
      await app.open();
      await set(app);
      await app.tapPebble('food');
      return containerOf(tester).read(timingsProvider).single.method;
    }

    testWidgets('pad', (tester) async {
      expect(
        await methodAfter(tester, (app) => app.type('45')),
        AmountMethod.pad,
      );
    });

    testWidgets('chips', (tester) async {
      expect(
        await methodAfter(tester, (app) async {
          await app.type('45');
          await tester.tap(find.byKey(LogFlow.chipKey(rupees(650))));
          await tester.pump();
        }),
        AmountMethod.chips,
      );
    });

    testWidgets('ring', (tester) async {
      expect(
        await methodAfter(tester, (app) async {
          await tester.tap(find.byKey(LogFlow.chipKey(rupees(650))));
          await showRing(tester);
          await app.turnRing(math.pi / 4 + 0.05, speed: 1.2);
          expect(app.amountText, '₹680');
        }),
        AmountMethod.ring,
      );
    });
  });

  group('fitting the screen', () {
    const insets = FakeViewPadding(top: 49, bottom: 48);

    Future<void> expectNoOverflow(WidgetTester tester, Size size) async {
      expect(tester.takeException(), isNull);
      for (final c in seedCategories) {
        final r = tester.getRect(find.byKey(LogFlow.pebbleKey(c.id)));
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(size.width));
      }
      final cancel = tester.getRect(find.byKey(LogFlow.cancelKey));
      expect(cancel.right, lessThanOrEqualTo(size.width));
      expect(
        tester.getRect(find.byKey(LogFlow.spendKey)).left,
        greaterThanOrEqualTo(0),
      );
    }

    testWidgets('412x915 with system bars: everything fits without '
        'scrolling in Pad and in Ring mode', (tester) async {
      tester.view.padding = insets;
      final app = await pumpLogApp(tester);
      await app.open();
      await expectNoOverflow(tester, const Size(412, 915));
      expect(maxScroll(tester), 0);
      expect(
        tester.getRect(find.byKey(LogFlow.pebbleKey('health'))).bottom,
        lessThanOrEqualTo(915 - 48),
      );
      expect(
        tester.getRect(find.byKey(LogFlow.cancelKey)).top,
        greaterThanOrEqualTo(49),
      );

      await showRing(tester);
      await expectNoOverflow(tester, const Size(412, 915));
      expect(maxScroll(tester), 0);

      // Income mode and an open note still fit.
      await tester.tap(find.byKey(LogFlow.incomeKey));
      await tester.tap(find.byKey(LogFlow.addNoteKey));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(maxScroll(tester), 0);
    });

    testWidgets('360x640: no overflow in Pad or Ring mode', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      final app = await pumpLogApp(tester, size: const Size(360, 640));
      await app.open();
      await expectNoOverflow(tester, const Size(360, 640));
      await showRing(tester);
      await expectNoOverflow(tester, const Size(360, 640));
      await tester.tap(find.byKey(LogFlow.addNoteKey));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('text scale 1.5: no overflow at 412x915 or 360x640', (
      tester,
    ) async {
      for (final size in const [Size(412, 915), Size(360, 640)]) {
        tester.view.padding = insets;
        final app = await pumpLogApp(tester, size: size, textScale: 1.5);
        await app.open();
        await expectNoOverflow(tester, size);
        await app.type('999999');
        await showRing(tester);
        await expectNoOverflow(tester, size);
        await tester.tap(find.byKey(LogFlow.incomeKey));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('on a screen that has to scroll, filing still works and '
        'turning the ring does not scroll the page', (tester) async {
      final app = await pumpLogApp(
        tester,
        size: const Size(360, 520),
        textScale: 1.5,
      );
      await app.open();
      expect(maxScroll(tester), greaterThan(0));
      await showRing(tester);
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(LogFlow.scrollKey),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      await app.turnRing(math.pi / 2 + 0.05, speed: 1.2);
      expect(position.pixels, 0);
      expect(app.amountText, '₹60');
      await app.tapPebble('health');
      expect(app.entries.last.categoryId, 'health');
      expect(tester.takeException(), isNull);
    });
  });
}
