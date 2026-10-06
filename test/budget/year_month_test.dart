// What these tests do and do not prove about Indian time.
//
// A test cannot change the time zone of the process it runs in. So:
//
// * "fixed offset" tests check the bounds arithmetic for UTC+05:30 on any
//   machine, with instants written in UTC. They prove the rule, not that the
//   platform applies it.
// * "device zone" tests check `monthUtcBounds`, the function the app really
//   uses, against local `DateTime`s in whatever zone the machine is in. They
//   prove the local-to-UTC conversion is consistent, in that zone only.
// * "when the machine is on Indian time" tests run only if the process's zone
//   is UTC+05:30 and are skipped otherwise. Run them with
//   `TZ=Asia/Kolkata flutter test test/budget/year_month_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:tide/budget/budget.dart';

const _ist = Duration(hours: 5, minutes: 30);

void main() {
  group('YearMonth', () {
    test('text form and parsing', () {
      expect(const YearMonth(2026, 10).key, '2026-10');
      expect(const YearMonth(2026, 3).key, '2026-03');
      expect('${const YearMonth(987, 1)}', '0987-01');
      expect(YearMonth.parse('2026-03'), const YearMonth(2026, 3));
      for (final bad in ['2026-13', '2026-00', '2026-3', '26-03', 'x', '']) {
        expect(YearMonth.tryParse(bad), isNull, reason: bad);
      }
      expect(() => YearMonth.parse('2026/03'), throwsFormatException);
    });

    test('ordering, including across a year boundary', () {
      const dec = YearMonth(2026, 12);
      const jan = YearMonth(2027, 1);
      expect(dec.isBefore(jan), isTrue);
      expect(jan.isAfter(dec), isTrue);
      expect(dec.next, jan);
      expect(jan.previous, dec);
      expect(const YearMonth(2026, 5).next, const YearMonth(2026, 6));
      expect(const YearMonth(2026, 5).previous, const YearMonth(2026, 4));
      final sorted = [jan, const YearMonth(2026, 2), dec]..sort();
      expect(sorted, [const YearMonth(2026, 2), dec, jan]);
      // The text form sorts the same way, which the budgets table relies on.
      expect(dec.key.compareTo(jan.key), lessThan(0));
      expect(dec == YearMonth.parse('2026-12'), isTrue);
      expect(dec.hashCode, YearMonth.parse('2026-12').hashCode);
    });

    test('of() reads the month from the fields of the DateTime given', () {
      expect(
        YearMonth.of(DateTime(2026, 10, 31, 23, 50)),
        const YearMonth(2026, 10),
      );
      expect(
        YearMonth.of(DateTime(2026, 11, 1, 0, 10)),
        const YearMonth(2026, 11),
      );
    });

    test('local start and end', () {
      const oct = YearMonth(2026, 10);
      expect(oct.localStart, DateTime(2026, 10, 1));
      expect(oct.localEnd, DateTime(2026, 11, 1));
      expect(const YearMonth(2026, 12).localEnd, DateTime(2027, 1, 1));
      expect(oct.localStart.isUtc, isFalse);
    });
  });

  group('Month bounds, fixed offset of +05:30 (Indian time)', () {
    final october = monthUtcBoundsAtOffset(const YearMonth(2026, 10), _ist);
    final november = monthUtcBoundsAtOffset(const YearMonth(2026, 11), _ist);

    test('October 2026 runs from 18:30 UTC on 30 September to 18:30 UTC on '
        '31 October', () {
      expect(october.startUtc, DateTime.utc(2026, 9, 30, 18, 30));
      expect(october.endUtc, DateTime.utc(2026, 10, 31, 18, 30));
      expect(october.endUtc, november.startUtc);
    });

    test('00:10 on 1 November, Indian time, is in November although it is '
        'still 31 October in UTC', () {
      final instant = DateTime.utc(2026, 11, 1, 0, 10).subtract(_ist);
      expect(instant, DateTime.utc(2026, 10, 31, 18, 40));
      expect(instant.month, 10, reason: 'still October in UTC');
      expect(november.contains(instant), isTrue);
      expect(october.contains(instant), isFalse);
    });

    test('23:50 on 31 October, Indian time, is in October', () {
      final instant = DateTime.utc(2026, 10, 31, 23, 50).subtract(_ist);
      expect(instant, DateTime.utc(2026, 10, 31, 18, 20));
      expect(october.contains(instant), isTrue);
      expect(november.contains(instant), isFalse);
    });

    test('the first instant is in, the end instant is out', () {
      expect(october.containsMillis(october.startMillis), isTrue);
      expect(october.containsMillis(october.startMillis - 1), isFalse);
      expect(october.containsMillis(october.endMillis - 1), isTrue);
      expect(october.containsMillis(october.endMillis), isFalse);
    });

    test('December bounds cross the year', () {
      final december = monthUtcBoundsAtOffset(const YearMonth(2026, 12), _ist);
      expect(december.endUtc, DateTime.utc(2026, 12, 31, 18, 30));
      expect(
        december.contains(DateTime.utc(2027, 1, 1, 0, 10).subtract(_ist)),
        isFalse,
      );
    });

    test(
      'bounds built from local start and end instants use their toUtc()',
      () {
        // Instants standing for midnight on 1 October and 1 November in India.
        final bounds = MonthUtcBounds(
          start: DateTime.utc(2026, 9, 30, 18, 30),
          end: DateTime.utc(2026, 10, 31, 18, 30),
        );
        expect(bounds, october);
        expect(bounds.startUtc.isUtc, isTrue);
      },
    );
  });

  group('Month bounds, device zone', () {
    const oct = YearMonth(2026, 10);
    const nov = YearMonth(2026, 11);
    final october = monthUtcBounds(oct);
    final november = monthUtcBounds(nov);

    test('bounds are the local month edges converted to UTC', () {
      expect(october.startUtc, DateTime(2026, 10, 1).toUtc());
      expect(october.endUtc, DateTime(2026, 11, 1).toUtc());
      expect(october.startUtc.isUtc, isTrue);
      expect(october.endMillis, november.startMillis);
    });

    test('00:10 local on 1 November is in November; 23:50 local on '
        '31 October is in October', () {
      final justAfter = DateTime(2026, 11, 1, 0, 10);
      final justBefore = DateTime(2026, 10, 31, 23, 50);
      expect(november.contains(justAfter), isTrue);
      expect(october.contains(justAfter), isFalse);
      expect(october.contains(justBefore), isTrue);
      expect(november.contains(justBefore), isFalse);
      // The same instants expressed in UTC give the same answers.
      expect(november.contains(justAfter.toUtc()), isTrue);
      expect(october.contains(justBefore.toUtc()), isTrue);
    });

    test('membership agrees with the local calendar for every hour of a '
        'year', () {
      var t = DateTime(2026, 1, 1);
      final end = DateTime(2027, 1, 1);
      while (t.isBefore(end)) {
        final month = YearMonth.of(t);
        expect(monthUtcBounds(month).contains(t), isTrue, reason: '$t');
        expect(monthUtcBounds(month.next).contains(t), isFalse, reason: '$t');
        expect(
          monthUtcBounds(month.previous).contains(t),
          isFalse,
          reason: '$t',
        );
        t = t.add(const Duration(hours: 1));
      }
    });
  });

  group('Month bounds, when the machine is on Indian time', () {
    final onIndianTime =
        DateTime(2026, 10, 15).timeZoneOffset == _ist &&
        DateTime(2026, 4, 15).timeZoneOffset == _ist;
    final skip = onIndianTime
        ? null
        : 'process zone is not UTC+05:30; run with TZ=Asia/Kolkata';

    test('the device-zone bounds equal the fixed-offset ones', () {
      expect(
        monthUtcBounds(const YearMonth(2026, 10)),
        monthUtcBoundsAtOffset(const YearMonth(2026, 10), _ist),
      );
    }, skip: skip);

    test('00:10 on 1 November local is 18:40 UTC on 31 October and counts '
        'toward November; 23:50 on 31 October counts toward October', () {
      final justAfter = DateTime(2026, 11, 1, 0, 10);
      expect(justAfter.toUtc(), DateTime.utc(2026, 10, 31, 18, 40));
      expect(
        monthUtcBounds(const YearMonth(2026, 11)).contains(justAfter),
        isTrue,
      );
      expect(
        monthUtcBounds(const YearMonth(2026, 10)).contains(justAfter),
        isFalse,
      );
      final justBefore = DateTime(2026, 10, 31, 23, 50);
      expect(
        monthUtcBounds(const YearMonth(2026, 10)).contains(justBefore),
        isTrue,
      );
    }, skip: skip);
  });
}
