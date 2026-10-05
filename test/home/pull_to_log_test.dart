import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide/home/home_screen.dart';
import 'package:tide/home/pull_to_log.dart';
import 'package:tide/home/timings_sheet.dart';
import 'package:tide/log/log_flow.dart';
import 'package:tide/state/budget_state.dart';
import 'package:tide/vessel/vessel_layer.dart';

import '../support/log_helpers.dart';
import '../support/pump_home.dart';

void main() {
  const middle = Offset(206, 500);

  group('opening the log flow', () {
    testWidgets('a 100 pixel drag down on the Vessel opens it in expense '
        'mode at ₹0', (tester) async {
      final app = await pumpLogApp(tester);
      await tester.dragFrom(middle, const Offset(0, 100));
      await app.settle();

      expect(app.isOpen, isTrue);
      expect(find.byKey(HomeScreen.overlaySlotKey), findsOneWidget);
      expect(find.byType(LogFlow), findsOneWidget);
      expect(app.amountText, '₹0');
      // Expense mode: the category pebbles, not the income sources.
      expect(find.byKey(LogFlow.pebbleKey('food')), findsOneWidget);
      expect(find.byKey(LogFlow.sourceKey('Salary')), findsNothing);
    });

    testWidgets('a 40 pixel drag does nothing', (tester) async {
      final app = await pumpLogApp(tester);
      await tester.dragFrom(middle, const Offset(0, 40));
      await app.settle();
      expect(app.isOpen, isFalse);
      expect(find.byType(LogFlow), findsNothing);
      expect(find.text('₹13,601'), findsOneWidget);
    });

    testWidgets('the threshold is 80 pixels of travel from where the finger '
        'went down', (tester) async {
      expect(PullToLog.threshold, 80);
      final app = await pumpLogApp(tester);
      await tester.dragFrom(middle, const Offset(0, 78));
      await app.settle();
      expect(app.isOpen, isFalse);
      await tester.dragFrom(middle, const Offset(0, 82));
      await app.settle();
      expect(app.isOpen, isTrue);
    });

    testWidgets('pulling down and back up again does not open', (tester) async {
      final app = await pumpLogApp(tester);
      final g = await tester.startGesture(middle);
      await g.moveBy(const Offset(0, 60));
      await g.moveBy(const Offset(0, 60));
      await g.moveBy(const Offset(0, -90));
      await g.up();
      await app.settle();
      expect(app.isOpen, isFalse);
    });

    testWidgets('an upward or sideways drag does not open', (tester) async {
      final app = await pumpLogApp(tester);
      await tester.dragFrom(middle, const Offset(0, -150));
      await tester.dragFrom(middle, const Offset(150, 0));
      await app.settle();
      expect(app.isOpen, isFalse);
    });

    testWidgets('a droplet follows the finger and says when to let go', (
      tester,
    ) async {
      final app = await pumpLogApp(tester);
      expect(find.byKey(PullToLog.dropletKey), findsNothing);

      final g = await tester.startGesture(middle);
      await g.moveBy(const Offset(0, 25));
      await g.moveBy(const Offset(0, 25));
      await tester.pump();
      expect(find.text('Keep pulling'), findsOneWidget);
      final early = tester.getCenter(find.byKey(PullToLog.dropletKey));

      await g.moveBy(const Offset(20, 50));
      await tester.pump();
      expect(find.text('Release to log'), findsOneWidget);
      final late = tester.getCenter(find.byKey(PullToLog.dropletKey));
      expect(late.dy, greaterThan(early.dy + 30));
      expect(late.dx, closeTo(early.dx + 20, 0.01));

      await g.up();
      await app.settle();
      expect(find.byKey(PullToLog.dropletKey), findsNothing);
      expect(app.isOpen, isTrue);
    });

    testWidgets('a drag that starts in the top safe-area inset is left to '
        'the system', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 48, bottom: 24);
      final app = await pumpLogApp(tester);
      await tester.dragFrom(const Offset(206, 20), const Offset(0, 200));
      await app.settle();
      expect(app.isOpen, isFalse);

      await tester.dragFrom(const Offset(206, 60), const Offset(0, 200));
      await app.settle();
      expect(app.isOpen, isTrue);
    });

    testWidgets('tapping the handle opens it in expense mode', (tester) async {
      final app = await pumpLogApp(tester);
      expect(find.text('Pull down to log'), findsOneWidget);
      await tester.tap(find.byKey(LogHandle.handleKey));
      await app.settle();
      expect(app.isOpen, isTrue);
      expect(app.amountText, '₹0');
      expect(find.byKey(LogFlow.pebbleKey('health')), findsOneWidget);
    });

    testWidgets('pulling down on the handle itself opens it too', (
      tester,
    ) async {
      final app = await pumpLogApp(tester);
      await tester.drag(find.byKey(LogHandle.handleKey), const Offset(0, 120));
      await app.settle();
      expect(app.isOpen, isTrue);
    });

    testWidgets('the handle sits below the top inset, is at least 44 tall '
        'and is labelled', (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.padding = const FakeViewPadding(top: 48, bottom: 24);
      await pumpLogApp(tester);
      final handle = tester.getRect(find.byKey(LogHandle.handleKey));
      expect(handle.top, greaterThanOrEqualTo(48));
      expect(handle.height, greaterThanOrEqualTo(44));
      expect(handle.width, greaterThanOrEqualTo(44));
      expect(
        handle.bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(VesselLayer.figuresKey)).top,
        ),
      );
      final node = tester.getSemantics(
        find.bySemanticsLabel('Pull down to log an expense'),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      semantics.dispose();
    });

    testWidgets('the handle and the Timings control fit a small screen at '
        'large text', (tester) async {
      await pumpLogApp(tester, size: const Size(320, 568), textScale: 2);
      expect(tester.takeException(), isNull);
      final handle = tester.getRect(find.byKey(LogHandle.handleKey));
      final timings = tester.getRect(find.byKey(TimingsButton.buttonKey));
      expect(handle.left, greaterThanOrEqualTo(0));
      expect(timings.right, lessThanOrEqualTo(320));
    });

    testWidgets('where the Vessel has to scroll, it still scrolls, the '
        'handle still opens, and a pull past its top opens', (tester) async {
      final app = await pumpLogApp(
        tester,
        size: const Size(320, 568),
        textScale: 2,
      );
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(VesselLayer),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));

      // Dragging up scrolls the Vessel and opens nothing.
      await tester.dragFrom(const Offset(160, 400), const Offset(0, -120));
      await app.settle();
      expect(scrollable.position.pixels, greaterThan(0));
      expect(app.isOpen, isFalse);

      // Dragging down a little scrolls it back and still opens nothing.
      await tester.dragFrom(const Offset(160, 300), const Offset(0, 60));
      await app.settle();
      expect(app.isOpen, isFalse);

      // At the top, a long pull opens the log flow.
      scrollable.position.jumpTo(0);
      await tester.pump();
      await tester.dragFrom(const Offset(160, 200), const Offset(0, 160));
      await app.settle();
      expect(app.isOpen, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('a pull on a Vessel that layout left a hair too tall', () {
    // Seen on the emulator: the Vessel's scroll extent came out as 1e-13
    // rather than 0, and an upward wobble of under a pixel as the finger
    // lifted then counted as the Vessel scrolling, which threw the pull away.
    Future<List<int>> pumpPull(WidgetTester tester) async {
      final opened = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: PullToLog(
            onOpen: () => opened.add(1),
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: SizedBox(height: box.maxHeight + 1e-11),
              ),
            ),
          ),
        ),
      );
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      expect(position.maxScrollExtent, greaterThan(0));
      expect(position.maxScrollExtent, lessThan(1e-9));
      return opened;
    }

    testWidgets('a slight upward wobble before letting go still opens', (
      tester,
    ) async {
      final opened = await pumpPull(tester);
      final g = await tester.startGesture(const Offset(200, 300));
      await g.moveBy(const Offset(0, 30));
      await g.moveBy(const Offset(0, 100));
      await g.moveBy(const Offset(0, -0.7));
      await tester.pump();
      expect(find.text('Release to log'), findsOneWidget);
      await g.up();
      await tester.pumpAndSettle();
      expect(opened, hasLength(1));
    });

    testWidgets('coming most of the way back up calls the pull off', (
      tester,
    ) async {
      final opened = await pumpPull(tester);
      final g = await tester.startGesture(const Offset(200, 300));
      await g.moveBy(const Offset(0, 30));
      await g.moveBy(const Offset(0, 150));
      await tester.pump();
      expect(find.text('Release to log'), findsOneWidget);
      await g.moveBy(const Offset(0, -110));
      await tester.pump();
      expect(find.text('Keep pulling'), findsOneWidget);
      await g.up();
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
    });
  });

  group('leaving the log flow', () {
    testWidgets('Cancel with an amount set returns to the Vessel and records '
        'nothing', (tester) async {
      final app = await pumpLogApp(tester);
      final before = containerOf(tester).read(budgetProvider);
      final snapshot = app.snapshot;

      await app.open();
      await app.type('250');
      expect(app.amountText, '₹250');
      await tester.tap(find.byKey(LogFlow.cancelKey));
      await app.settle();

      expect(app.isOpen, isFalse);
      expect(find.byType(LogFlow), findsNothing);
      expect(find.byKey(HomeScreen.overlaySlotKey), findsNothing);
      expect(containerOf(tester).read(budgetProvider), before);
      expect(app.snapshot, snapshot);
      expect(find.text('₹13,601'), findsOneWidget);
      expect(app.haptics.calls, isEmpty);
    });

    testWidgets('the system back button closes it without recording', (
      tester,
    ) async {
      final app = await pumpLogApp(tester);
      final count = app.entries.length;
      await app.open();
      await app.type('99');
      await tester.binding.handlePopRoute();
      await app.settle();
      expect(app.isOpen, isFalse);
      expect(find.byType(LogFlow), findsNothing);
      expect(app.entries.length, count);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('reopening starts again at ₹0 in expense mode', (tester) async {
      final app = await pumpLogApp(tester);
      await app.open();
      await app.type('480');
      await tester.tap(find.byKey(LogFlow.incomeKey));
      await tester.pump();
      await tester.tap(find.byKey(LogFlow.cancelKey));
      // Reopen before the exit animation has finished.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(LogHandle.handleKey));
      await app.settle();
      expect(app.amountText, '₹0');
      expect(find.byKey(LogFlow.pebbleKey('food')), findsOneWidget);
    });

    testWidgets('it fades in and out over about 200 ms', (tester) async {
      final app = await pumpLogApp(tester);
      await tester.tap(find.byKey(LogHandle.handleKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final fade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.byType(LogFlow),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 120));
      expect(fade.opacity.value, 1);

      await tester.tap(find.byKey(LogFlow.cancelKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(LogFlow), findsOneWidget, reason: 'still leaving');
      await app.settle();
      expect(find.byType(LogFlow), findsNothing);
    });

    testWidgets('with reduce-motion on it appears and goes at once', (
      tester,
    ) async {
      await pumpLogApp(tester, still: true);
      await tester.tap(find.byKey(LogHandle.handleKey));
      await tester.pump();
      final fade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.byType(LogFlow),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, 1);
      await tester.tap(find.byKey(LogFlow.cancelKey));
      await tester.pump();
      expect(find.byType(LogFlow), findsNothing);
    });
  });
}
