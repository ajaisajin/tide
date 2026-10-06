import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tide/budget/budget.dart';
import 'package:tide/home/home_screen.dart';
import 'package:tide/home/log_flow_state.dart';
import 'package:tide/state/budget_state.dart';
import 'package:tide/theme/tide_theme.dart';
import 'package:tide/vessel/liquid_motion.dart';
import 'package:tide/vessel/liquid_painter.dart';
import 'package:tide/vessel/pebble.dart';
import 'package:tide/vessel/still_water.dart';
import 'package:tide/vessel/vessel_geometry.dart';
import 'package:tide/vessel/vessel_layer.dart';

import '../support/pump_home.dart';

void main() {
  BudgetNotifier budget(WidgetTester tester) =>
      containerOf(tester).read(budgetProvider.notifier);

  Rect pebbleRect(WidgetTester tester, String id) =>
      tester.getRect(find.byKey(CategoryPebble.bodyKey(id)));

  Color pebbleOutline(WidgetTester tester, String id) {
    final body = tester.widget<AnimatedContainer>(
      find.byKey(CategoryPebble.bodyKey(id)),
    );
    final border = (body.decoration! as BoxDecoration).border! as Border;
    return border.top.color;
  }

  double fontSizeOf(WidgetTester tester, Finder text) {
    final rich = tester.widget<RichText>(
      find.descendant(of: text, matching: find.byType(RichText)),
    );
    return rich.text.style!.fontSize! * rich.textScaler.scale(1);
  }

  group('figures', () {
    testWidgets('opening the app mid-month shows every figure untapped', (
      tester,
    ) async {
      await pumpHome(tester);

      expect(find.text('₹13,601'), findsOneWidget);
      expect(find.text('October'), findsOneWidget);
      expect(find.text('Running lower'), findsOneWidget);
      expect(find.text('left of ₹30,000'), findsOneWidget);
      expect(find.text('45% full'), findsOneWidget);
      expect(find.text('Safe today: ₹503'), findsOneWidget);
    });

    testWidgets('month and mood are painted in capitals', (tester) async {
      await pumpHome(tester);
      expect(find.text('OCTOBER'), findsOneWidget);
      expect(find.text('RUNNING LOWER'), findsOneWidget);
    });

    testWidgets('the remaining amount is the largest text, in the display '
        'face at bold weight', (tester) async {
      await pumpHome(tester);
      final hero = fontSizeOf(tester, find.byKey(VesselLayer.remainingKey));
      final all = tester.widgetList<RichText>(
        find.descendant(
          of: find.byType(VesselLayer),
          matching: find.byType(RichText),
        ),
      );
      final sizes = [
        for (final t in all) t.text.style!.fontSize! * t.textScaler.scale(1),
      ]..sort();
      expect(sizes.last, hero);
      expect(sizes[sizes.length - 2], lessThan(hero));

      final style = tester
          .widget<RichText>(
            find.descendant(
              of: find.byKey(VesselLayer.remainingKey),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style!;
      expect(style.fontFamily, TideText.displayFamily);
      expect(style.fontWeight, FontWeight.w700);
      expect(style.fontVariations, contains(const FontVariation('wght', 700)));
    });

    testWidgets('the month comes from the clock', (tester) async {
      await pumpHome(tester, now: DateTime(2027, 2, 14, 9));
      expect(find.text('February'), findsOneWidget);
    });

    testWidgets('figures follow the state', (tester) async {
      await pumpHome(tester);
      budget(tester).addIncome(amountMinor: rupees(5000), note: 'Freelance');
      await tester.pump();

      expect(find.text('₹18,601'), findsOneWidget);
      expect(find.text('left of ₹35,000'), findsOneWidget);
      expect(find.text('53% full'), findsOneWidget);
      expect(find.text('Calm water'), findsOneWidget);
    });

    testWidgets('a debug frame-rate readout is present', (tester) async {
      await pumpHome(tester);
      await pumpFor(tester, const Duration(milliseconds: 700));
      final readout = tester.widget<Text>(find.byKey(VesselLayer.frameRateKey));
      expect(readout.data, contains('fps'));
    });
  });

  group('pebbles', () {
    testWidgets('six pebbles show name and spend', (tester) async {
      await pumpHome(tester);
      for (final (name, spend) in [
        ('Food', '₹2,330'),
        ('Bills', '₹10,400'),
        ('Travel', '₹670'),
        ('Shopping', '₹1,850'),
        ('Fun', '₹499'),
        ('Health', '₹650'),
      ]) {
        expect(find.text(name), findsOneWidget);
        expect(find.text(spend), findsOneWidget);
      }
      expect(find.byType(CategoryPebble), findsNWidgets(6));
    });

    testWidgets('a pebble at 90% of its limit is larger than one at 33%', (
      tester,
    ) async {
      CategoryPosition at(String id, int spent) => CategoryPosition(
        category: Category(
          id: id,
          name: id,
          colorValue: 0xFF9EE6C3,
          limitMinor: rupees(1000),
        ),
        spentMinor: rupees(spent),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: PebbleField(
              width: 380,
              categories: [at('ninety', 900), at('third', 330), at('none', 0)],
            ),
          ),
        ),
      );
      final ninety = tester.getSize(
        find.byKey(CategoryPebble.bodyKey('ninety')),
      );
      final third = tester.getSize(find.byKey(CategoryPebble.bodyKey('third')));
      final none = tester.getSize(find.byKey(CategoryPebble.bodyKey('none')));

      expect(ninety.width, closeTo(64 + 0.9 * 34, 0.01));
      expect(third.width, closeTo(64 + 0.33 * 34, 0.01));
      expect(ninety.width, greaterThan(third.width));
      expect(ninety.height, ninety.width);
      expect(none.width, 64);
    });

    testWidgets('seeded pebbles: Shopping (93%) is larger than Fun (33%) and '
        'none is below 64', (tester) async {
      await pumpHome(tester);
      expect(
        pebbleRect(tester, 'shop').width,
        greaterThan(pebbleRect(tester, 'fun').width),
      );
      for (final id in ['food', 'bills', 'travel', 'shop', 'fun', 'health']) {
        expect(pebbleRect(tester, id).width, greaterThanOrEqualTo(64));
        expect(pebbleRect(tester, id).height, greaterThanOrEqualTo(64));
      }
    });

    testWidgets('pebbles keep the 64 pixel minimum on a narrow screen', (
      tester,
    ) async {
      await pumpHome(tester, size: const Size(320, 568));
      for (final id in ['food', 'bills', 'travel', 'shop', 'fun', 'health']) {
        final rect = pebbleRect(tester, id);
        expect(rect.width, greaterThanOrEqualTo(64));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
      }
    });

    testWidgets('an over-limit pebble sits lower with a coral outline', (
      tester,
    ) async {
      await pumpHome(tester);
      // Shopping, Fun and Health share the second row, bottoms aligned.
      expect(
        pebbleRect(tester, 'shop').bottom,
        closeTo(pebbleRect(tester, 'fun').bottom, 0.01),
      );
      expect(pebbleOutline(tester, 'shop'), const Color(0xFFF29BB8));
      final healthBefore = pebbleRect(tester, 'health').bottom;

      budget(tester).addExpense(amountMinor: rupees(400), categoryId: 'shop');
      await pumpFor(tester, const Duration(milliseconds: 700));

      final shop = pebbleRect(tester, 'shop');
      final fun = pebbleRect(tester, 'fun');
      expect(shop.bottom - fun.bottom, closeTo(pebbleSunkOffset, 0.01));
      expect(pebbleOutline(tester, 'shop'), TideColors.coral);
      expect(pebbleOutline(tester, 'fun'), const Color(0xFF9EE6C3));
      expect(find.text('₹2,250'), findsOneWidget);
      // The sunk pebble stays on screen and the others have not jumped down.
      expect(shop.bottom, lessThanOrEqualTo(915));
      expect(
        pebbleRect(tester, 'health').bottom,
        lessThanOrEqualTo(healthBefore),
      );
    });

    testWidgets('a sunk pebble in the first row does not land on the second', (
      tester,
    ) async {
      await pumpHome(tester);
      budget(tester).addExpense(amountMinor: rupees(4000), categoryId: 'food');
      await pumpFor(tester, const Duration(milliseconds: 700));

      final food = pebbleRect(tester, 'food');
      expect(pebbleOutline(tester, 'food'), TideColors.coral);
      expect(food.bottom, greaterThan(pebbleRect(tester, 'bills').bottom));
      expect(food.bottom, lessThanOrEqualTo(pebbleRect(tester, 'shop').top));
    });

    testWidgets('near the limit has no special look', (tester) async {
      await pumpHome(tester);
      final bills = containerOf(
        tester,
      ).read(budgetSnapshotProvider).categoryById('bills')!;
      expect(bills.nearLimit, isTrue);
      expect(pebbleOutline(tester, 'bills'), const Color(0xFFC7A6F2));
      expect(
        pebbleRect(tester, 'bills').bottom,
        closeTo(pebbleRect(tester, 'food').bottom, 0.01),
      );
    });
  });

  group('liquid level', () {
    testWidgets('seeded data puts the liquid at 45% of its range', (
      tester,
    ) async {
      await pumpHome(tester);
      final motion = liquidMotion(tester);
      final floor = 915 * liquidFloorFraction;
      expect(motion.height, greaterThan(floor));
      expect(liquidPainter(tester), isA<PathLiquidPainter>());

      // Empty the vessel's spending to find the top of the range.
      final level = motion.height;
      for (var i = 1; i <= 12; i++) {
        budget(tester).removeEntry('seed-$i');
      }
      await tester.pump();
      await tester.pump();
      final full = liquidMotion(tester).targetHeight;
      expect((level - floor) / (full - floor), closeTo(13601 / 30000, 0.001));
    });

    testWidgets('at fill level 1 the liquid stays clear of the figures', (
      tester,
    ) async {
      await pumpHome(tester);
      for (var i = 1; i <= 12; i++) {
        budget(tester).removeEntry('seed-$i');
      }
      await pumpFor(tester, const Duration(milliseconds: 1500));

      expect(find.text('100% full'), findsOneWidget);
      final motion = liquidMotion(tester);
      final surface = 915 - motion.height;
      final figures = tester.getRect(find.byKey(VesselLayer.figuresKey));
      // Even leaning as far as it can and mid-slosh, the surface is below.
      final highest = surface - LiquidMotion.maxLean * 412 / 2 - 20;
      expect(highest, greaterThan(figures.bottom));
      expect(
        tester.getRect(find.byKey(VesselLayer.remainingKey)).bottom,
        lessThan(highest),
      );
      expect(motion.height, greaterThan(915 * 0.5), reason: 'visibly full');
    });

    testWidgets('at fill level 1 with text scale 2 on a small screen the '
        'liquid still stays below the figures', (tester) async {
      await pumpHome(tester, size: const Size(320, 568), textScale: 2);
      for (var i = 1; i <= 12; i++) {
        budget(tester).removeEntry('seed-$i');
      }
      await pumpFor(tester, const Duration(milliseconds: 1500));
      final surface = 568 - liquidMotion(tester).height;
      final hero = tester.getRect(find.byKey(VesselLayer.remainingKey));
      expect(surface, greaterThan(hero.bottom));
    });

    testWidgets('at fill level 0.02 a band of liquid is still there', (
      tester,
    ) async {
      await pumpHome(tester);
      budget(
        tester,
      ).addExpense(amountMinor: rupees(13001), categoryId: 'bills');
      await pumpFor(tester, const Duration(milliseconds: 1500));

      expect(find.text('2% full'), findsOneWidget);
      expect(liquidPainter(tester), isA<PathLiquidPainter>());
      final height = liquidMotion(tester).height;
      expect(height, greaterThan(915 * liquidFloorFraction));
      expect(height, lessThan(915 * 0.12));
    });

    testWidgets('an expense drains the liquid with a slosh that settles in '
        'about a second', (tester) async {
      await pumpHome(tester);
      final motion = liquidMotion(tester);
      final before = motion.height;

      budget(tester).addExpense(amountMinor: rupees(5000), categoryId: 'food');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final target = motion.targetHeight;
      expect(target, lessThan(before));

      await pumpFor(tester, const Duration(milliseconds: 150));
      expect(motion.height, lessThan(before));
      expect(motion.height, greaterThan(target), reason: 'on its way down');
      expect(motion.slosh.abs(), greaterThan(0.2), reason: 'surface disturbed');

      await pumpFor(tester, const Duration(milliseconds: 1050));
      expect(motion.height, closeTo(target, 1));
      expect(motion.slosh.abs(), lessThan(0.03));
    });

    testWidgets('income raises the liquid', (tester) async {
      await pumpHome(tester);
      final motion = liquidMotion(tester);
      final before = motion.height;

      budget(tester).addIncome(amountMinor: rupees(5000));
      await pumpFor(tester, const Duration(milliseconds: 200));
      expect(motion.targetHeight, greaterThan(before));
      expect(motion.height, greaterThan(before));
      await pumpFor(tester, const Duration(milliseconds: 1000));
      expect(motion.height, closeTo(motion.targetHeight, 1));
    });

    testWidgets('removing an entry brings the level back', (tester) async {
      await pumpHome(tester);
      final motion = liquidMotion(tester);
      final before = motion.height;
      final entry = await budget(
        tester,
      ).addExpense(amountMinor: rupees(3000), categoryId: 'bills');
      await pumpFor(tester, const Duration(milliseconds: 1200));
      expect(motion.height, lessThan(before - 5));

      budget(tester).removeEntry(entry.id);
      await pumpFor(tester, const Duration(milliseconds: 1200));
      expect(motion.height, closeTo(before, 1));
    });

    testWidgets('the liquid moves without the Vessel rebuilding', (
      tester,
    ) async {
      await pumpHome(tester);
      final canvas = tester.widget<CustomPaint>(
        find.byKey(VesselLayer.liquidCanvasKey),
      );
      final time = liquidMotion(tester).time;
      await pumpFor(tester, const Duration(milliseconds: 300));

      expect(liquidMotion(tester).time, greaterThan(time));
      expect(
        tester.widget<CustomPaint>(find.byKey(VesselLayer.liquidCanvasKey)),
        same(canvas),
        reason: 'same widget instance: nothing was rebuilt',
      );
      expect(
        find.ancestor(
          of: find.byKey(VesselLayer.liquidCanvasKey),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
    });
  });

  group('colour and mood', () {
    testWidgets('crossing 0.5 turns teal to amber and Calm water to Running '
        'lower', (tester) async {
      await pumpHome(tester);
      // ₹4,165 of income makes it ₹17,766 of ₹34,165: fill 0.52.
      budget(tester).addIncome(amountMinor: rupees(4165));
      await pumpFor(tester, const Duration(milliseconds: 1200));
      final motion = liquidMotion(tester);
      expect(find.text('52% full'), findsOneWidget);
      expect(find.text('Calm water'), findsOneWidget);
      expect(motion.color, TideColors.teal);

      // ₹1,367 spent leaves ₹16,399: fill 0.48.
      budget(tester).addExpense(amountMinor: rupees(1367), categoryId: 'food');
      await tester.pump();
      expect(find.text('48% full'), findsOneWidget);
      expect(find.text('Running lower'), findsOneWidget);
      expect(find.text('Calm water'), findsNothing);
      expect(motion.targetColor, TideColors.amber);

      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(motion.color, isNot(TideColors.teal));
      expect(motion.color, isNot(TideColors.amber), reason: 'mid cross-fade');
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(motion.color, TideColors.amber);
    });

    testWidgets('crossing 0.25 turns the liquid coral and says Nearly dry', (
      tester,
    ) async {
      await pumpHome(tester);
      budget(tester).addExpense(amountMinor: rupees(8000), categoryId: 'bills');
      await pumpFor(tester, const Duration(milliseconds: 1000));
      expect(find.text('Nearly dry'), findsOneWidget);
      expect(liquidMotion(tester).color, TideColors.coral);
      expect(liquidPainter(tester), isA<PathLiquidPainter>());
    });
  });

  group('overspent', () {
    testWidgets('overspent by ₹2,000 shows the negative amount, the band and '
        'Safe today: ₹0', (tester) async {
      await pumpHome(tester);
      expect(liquidPainter(tester), isNot(isA<OverspentBandPainter>()));

      budget(tester).addExpense(amountMinor: rupees(15601), categoryId: 'shop');
      await pumpFor(tester, const Duration(milliseconds: 1200));

      expect(find.text('−₹2,000'), findsOneWidget);
      expect(find.text('Below the line'), findsOneWidget);
      expect(find.text('Safe today: ₹0'), findsOneWidget);
      expect(find.text('0% full'), findsOneWidget);
      expect(find.text('over your ₹30,000'), findsOneWidget);
      expect(liquidPainter(tester), isA<OverspentBandPainter>());

      final hero = tester.widget<RichText>(
        find.descendant(
          of: find.byKey(VesselLayer.remainingKey),
          matching: find.byType(RichText),
        ),
      );
      expect(hero.text.style!.color, TideColors.overspentInk);
      expect(
        liquidMotion(tester).height,
        closeTo(
          overspentHeight(
            overByMinor: rupees(2000),
            availableMinor: rupees(30000),
            screenHeight: 915,
          ),
          1,
        ),
      );
    });

    testWidgets('the band grows as the overspend grows', (tester) async {
      await pumpHome(tester);
      budget(
        tester,
      ).addExpense(amountMinor: rupees(15601), categoryId: 'bills');
      await pumpFor(tester, const Duration(milliseconds: 1200));
      final small = liquidMotion(tester).height;

      budget(tester).addExpense(amountMinor: rupees(6000), categoryId: 'bills');
      await pumpFor(tester, const Duration(milliseconds: 1200));
      expect(find.text('−₹8,000'), findsOneWidget);
      expect(liquidMotion(tester).height, greaterThan(small + 20));
    });

    testWidgets('income that brings it back to ₹500 returns the liquid', (
      tester,
    ) async {
      await pumpHome(tester);
      budget(
        tester,
      ).addExpense(amountMinor: rupees(15601), categoryId: 'bills');
      await pumpFor(tester, const Duration(milliseconds: 1200));
      expect(liquidPainter(tester), isA<OverspentBandPainter>());

      budget(tester).addIncome(amountMinor: rupees(2500), note: 'Refund');
      await pumpFor(tester, const Duration(milliseconds: 1200));

      expect(find.text('₹500'), findsOneWidget);
      expect(find.text('Below the line'), findsNothing);
      expect(find.text('Nearly dry'), findsOneWidget);
      expect(find.text('left of ₹32,500'), findsOneWidget);
      expect(liquidPainter(tester), isA<PathLiquidPainter>());
      expect(liquidMotion(tester).color, TideColors.coral);
      final hero = tester.widget<RichText>(
        find.descendant(
          of: find.byKey(VesselLayer.remainingKey),
          matching: find.byType(RichText),
        ),
      );
      expect(hero.text.style!.color, TideColors.text);
    });
  });

  group('tilt', () {
    testWidgets('readings lean the surface, which levels when they stop', (
      tester,
    ) async {
      final tilt = await pumpHome(tester);
      expect(tilt.isListening, isTrue);
      expect(liquidMotion(tester).lean, 0);

      tilt.add(0.5);
      await pumpFor(tester, const Duration(milliseconds: 1200));
      expect(
        liquidMotion(tester).lean,
        closeTo(0.5 * LiquidMotion.leanPerRoll, 0.01),
      );

      tilt.add(0);
      await pumpFor(tester, const Duration(milliseconds: 1500));
      expect(liquidMotion(tester).lean, closeTo(0, 0.005));
    });

    testWidgets('the sensor is not read while the log flow is open, and is '
        'read again when it closes', (tester) async {
      final tilt = await pumpHome(tester);
      expect(tilt.isListening, isTrue);
      expect(tilt.listens, 1);

      containerOf(tester).read(logFlowOpenProvider.notifier).open();
      await tester.pump();
      expect(tilt.isListening, isFalse);
      expect(tilt.cancels, 1);

      // A reading that arrives anyway goes nowhere.
      tilt.add(0.9);
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(liquidMotion(tester).lean, closeTo(0, 0.005));

      containerOf(tester).read(logFlowOpenProvider.notifier).close();
      await tester.pump();
      expect(tilt.isListening, isTrue);
      expect(tilt.listens, 2);
    });

    testWidgets('the surface levels out when the log flow opens mid-tilt', (
      tester,
    ) async {
      final tilt = await pumpHome(tester);
      tilt.add(0.5);
      await pumpFor(tester, const Duration(milliseconds: 800));
      expect(liquidMotion(tester).lean.abs(), greaterThan(0.1));

      containerOf(tester).read(logFlowOpenProvider.notifier).open();
      await pumpFor(tester, const Duration(milliseconds: 1500));
      expect(liquidMotion(tester).lean, closeTo(0, 0.005));
    });

    testWidgets('a sensor error leaves the surface level and nothing breaks', (
      tester,
    ) async {
      final tilt = await pumpHome(tester);
      tilt.addError(StateError('no accelerometer'));
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(liquidMotion(tester).lean, 0);
      expect(find.text('₹13,601'), findsOneWidget);
    });

    testWidgets('all-zero readings, as on web, leave the surface level', (
      tester,
    ) async {
      final tilt = await pumpHome(tester);
      tilt.add(0);
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(liquidMotion(tester).lean, 0);
    });

    testWidgets('the sensor is not read while the app is in the background', (
      tester,
    ) async {
      final tilt = await pumpHome(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(tilt.isListening, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tilt.isListening, isTrue);
    });
  });

  group('still water', () {
    testWidgets('reduce motion uses the still painter and the level still '
        'updates, at once, with no slosh', (tester) async {
      final tilt = await pumpHome(tester, still: true);
      expect(liquidPainter(tester), isA<StillLiquidPainter>());
      final motion = liquidMotion(tester);
      expect(motion.still, isTrue);
      final before = motion.height;
      expect(before, greaterThan(915 * liquidFloorFraction));
      expect(motion.color, TideColors.amber);

      budget(tester).addExpense(amountMinor: rupees(8000), categoryId: 'food');
      await tester.pump();
      await tester.pump();

      expect(find.text('₹5,601'), findsOneWidget);
      expect(liquidPainter(tester), isA<StillLiquidPainter>());
      expect(motion.height, lessThan(before - 20));
      expect(motion.height, motion.targetHeight, reason: 'no animation');
      expect(motion.slosh, 0);
      expect(motion.lean, 0);
      expect(motion.color, TideColors.coral, reason: 'colour still follows');
      expect(tilt.listens, 0, reason: 'the sensor is never read');

      // Nothing is animating, so the app settles.
      await tester.pumpAndSettle();
    });

    testWidgets('sustained slow frames switch to still water, stop the '
        'sensor, and it stays that way', (tester) async {
      final tilt = await pumpHome(tester);
      expect(liquidPainter(tester), isA<PathLiquidPainter>());
      expect(tilt.isListening, isTrue);

      // What the frame-time monitor does when it trips.
      containerOf(tester).read(slowFramesProvider.notifier).trip();
      await tester.pump();

      expect(liquidPainter(tester), isA<StillLiquidPainter>());
      expect(tilt.isListening, isFalse);
      expect(liquidMotion(tester).still, isTrue);

      budget(tester).addIncome(amountMinor: rupees(5000));
      await tester.pump();
      await tester.pump();
      expect(liquidPainter(tester), isA<StillLiquidPainter>());
      expect(liquidMotion(tester).height, liquidMotion(tester).targetHeight);
      expect(containerOf(tester).read(slowFramesProvider), isTrue);
    });

    testWidgets('turning reduce motion off brings the moving liquid back', (
      tester,
    ) async {
      final tilt = await pumpHome(tester, still: true);
      expect(liquidPainter(tester), isA<StillLiquidPainter>());

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      await tester.pump();
      expect(liquidPainter(tester), isA<PathLiquidPainter>());
      expect(tilt.isListening, isTrue);
    });
  });

  group('semantics', () {
    testWidgets('one summary states percentage left, amount and safe today', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpHome(tester);

      final summary = find.bySemanticsLabel(RegExp('Budget'));
      expect(summary, findsOneWidget);
      final label = tester.getSemantics(summary).label;
      expect(label, contains('45% left'));
      expect(label, contains('₹13,601'));
      expect(label, contains('safe today ₹503'));
      expect(label, contains('October'));
      expect(label, contains('Running lower'));
      expect(
        label,
        'October, Running lower. Budget 45% left, ₹13,601 remaining of '
        '₹30,000, safe today ₹503',
      );

      // The figures are not read a second time one by one.
      expect(find.semantics.byLabel('₹13,601'), findsNothing);
      expect(find.semantics.byLabel(RegExp('13,601')), findsOne);
      expect(find.semantics.byLabel('45% full'), findsNothing);
      expect(find.semantics.byLabel(RegExp('fps')), findsNothing);
      expect(find.semantics.byLabel(RegExp('Food')), findsOne);
      handle.dispose();
    });

    testWidgets('each pebble is labelled with name, spend and limit', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpHome(tester);
      for (final label in [
        'Food, ₹2,330 of ₹6,000',
        'Bills, ₹10,400 of ₹11,000',
        'Travel, ₹670 of ₹3,000',
        'Shopping, ₹1,850 of ₹2,000',
        'Fun, ₹499 of ₹1,500',
        'Health, ₹650 of ₹1,500',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }
      expect(find.bySemanticsLabel(RegExp('over limit')), findsNothing);
      handle.dispose();
    });

    testWidgets('an over-limit pebble says so', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHome(tester);
      budget(tester).addExpense(amountMinor: rupees(400), categoryId: 'shop');
      await tester.pump();

      final pebble = find.bySemanticsLabel(RegExp('^Shopping'));
      expect(pebble, findsOneWidget);
      final label = tester.getSemantics(pebble).label;
      expect(label, contains('Shopping'));
      expect(label, contains('₹2,250'));
      expect(label, contains('₹2,000'));
      expect(label, contains('over limit'));
      handle.dispose();
    });

    testWidgets('the overspent summary gives the negative amount', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpHome(tester);
      budget(
        tester,
      ).addExpense(amountMinor: rupees(15601), categoryId: 'bills');
      await tester.pump();
      final label = tester
          .getSemantics(find.bySemanticsLabel(RegExp('Budget')))
          .label;
      expect(label, contains('Below the line'));
      expect(label, contains('0% left'));
      expect(label, contains('−₹2,000 remaining'));
      expect(label, contains('overspent by ₹2,000'));
      expect(label, contains('safe today ₹0'));
      handle.dispose();
    });

    testWidgets('pebbles have no tap action', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHome(tester);
      final node = tester.getSemantics(find.bySemanticsLabel(RegExp('^Food')));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    });
  });

  group('fitting the screen', () {
    Future<void> expectFits(WidgetTester tester, Size size) async {
      expect(tester.takeException(), isNull);
      final hero = tester.getRect(find.byKey(VesselLayer.remainingKey));
      expect(hero.left, greaterThanOrEqualTo(0));
      expect(hero.right, lessThanOrEqualTo(size.width));
      final figures = tester.getRect(find.byKey(VesselLayer.figuresKey));
      expect(figures.right, lessThanOrEqualTo(size.width));
    }

    testWidgets('no overflow at text scale 2.0', (tester) async {
      await pumpHome(tester, textScale: 2);
      await expectFits(tester, const Size(412, 915));
      // Everything still fits without scrolling on an ordinary phone.
      expect(pebbleRect(tester, 'health').bottom, lessThanOrEqualTo(915));
    });

    testWidgets('no overflow on a small 320x568 screen', (tester) async {
      await pumpHome(tester, size: const Size(320, 568));
      await expectFits(tester, const Size(320, 568));
      expect(pebbleRect(tester, 'health').bottom, lessThanOrEqualTo(568));
      expect(
        tester.getRect(find.byKey(VesselLayer.figuresKey)).bottom,
        lessThanOrEqualTo(pebbleRect(tester, 'food').top),
        reason: 'figures and pebbles do not overlap',
      );
    });

    testWidgets('no overflow on a small screen at text scale 2.0', (
      tester,
    ) async {
      await pumpHome(tester, size: const Size(320, 568), textScale: 2);
      await expectFits(tester, const Size(320, 568));
    });

    testWidgets('a seven-digit amount stays on one line inside the screen', (
      tester,
    ) async {
      for (final size in const [Size(412, 915), Size(320, 568)]) {
        await pumpHome(tester, size: size, textScale: 2);
        budget(tester).addIncome(amountMinor: rupees(5000000));
        await tester.pump();

        expect(find.text('₹50,13,601'), findsOneWidget);
        await expectFits(tester, size);
        final line = tester.getSize(find.byKey(VesselLayer.remainingKey));
        final one = tester.getSize(find.text('₹50,13,601'));
        expect(line.height, one.height);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('an overspent seven-digit amount fits too', (tester) async {
      await pumpHome(tester, size: const Size(320, 568));
      budget(
        tester,
      ).addExpense(amountMinor: rupees(1250000), categoryId: 'bills');
      await tester.pump();
      expect(find.text('−₹12,36,399'), findsOneWidget);
      await expectFits(tester, const Size(320, 568));
    });

    testWidgets('a wide window keeps the content in a centred column', (
      tester,
    ) async {
      await pumpHome(tester, size: const Size(1280, 800));
      expect(tester.takeException(), isNull);
      final figures = tester.getRect(find.byKey(VesselLayer.figuresKey));
      expect(figures.left, greaterThan(300));
      expect(figures.right, lessThan(980));
    });
  });

  group('home', () {
    testWidgets('the ink background fills the screen and the Vessel is '
        'always in the tree', (tester) async {
      await pumpHome(tester);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, TideColors.ink);
      expect(tester.getSize(find.byType(VesselLayer)), const Size(412, 915));
      expect(find.byKey(HomeScreen.overlaySlotKey), findsNothing);

      containerOf(tester).read(logFlowOpenProvider.notifier).open();
      await tester.pump();
      expect(find.byType(VesselLayer), findsOneWidget);
      expect(find.byKey(HomeScreen.overlaySlotKey), findsOneWidget);
      expect(find.byType(LogFlowPlaceholder), findsOneWidget);
      expect(
        tester.getSize(find.byType(LogFlowPlaceholder)),
        const Size(412, 915),
      );

      containerOf(tester).read(logFlowOpenProvider.notifier).close();
      await tester.pump();
      expect(find.byKey(HomeScreen.overlaySlotKey), findsNothing);
      expect(find.byType(VesselLayer), findsOneWidget);
    });

    testWidgets('a log flow builder fills the overlay slot', (tester) async {
      await pumpHome(
        tester,
        logFlowBuilder: (context) => const Center(child: Text('log flow')),
      );
      expect(find.text('log flow'), findsNothing);
      containerOf(tester).read(logFlowOpenProvider.notifier).open();
      await tester.pump();
      expect(find.text('log flow'), findsOneWidget);
      expect(find.byType(LogFlowPlaceholder), findsNothing);
    });

    testWidgets('the Vessel is hidden from screen readers while the log flow '
        'covers it', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHome(tester);
      expect(find.semantics.byLabel(RegExp('Budget')), findsOne);
      containerOf(tester).read(logFlowOpenProvider.notifier).open();
      await tester.pump();
      expect(find.semantics.byLabel(RegExp('Budget')), findsNothing);
      handle.dispose();
    });

    testWidgets('status-bar icons are light over the ink', (tester) async {
      await pumpHome(tester);
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
      );
      expect(region.value.statusBarIconBrightness, Brightness.light);
      expect(region.value.statusBarColor, Colors.transparent);
    });
  });
}
