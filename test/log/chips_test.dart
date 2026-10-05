import 'package:flutter_test/flutter_test.dart';
import 'package:tide/budget/budget.dart';
import 'package:tide/log/chips.dart';
import 'package:tide/state/seed.dart';

var _n = 0;

Entry spend(int amount, {int day = 1, int minute = 0}) => Entry(
  id: 'c-${_n++}',
  type: EntryType.expense,
  amountMinor: rupees(amount),
  categoryId: 'food',
  occurredAt: DateTime(2026, 10, day, 12, minute),
);

Entry income(int amount, {int day = 1}) => Entry(
  id: 'c-${_n++}',
  type: EntryType.income,
  amountMinor: rupees(amount),
  occurredAt: DateTime(2026, 10, day),
);

List<int> inRupees(List<int> minor) => [for (final m in minor) m ~/ 100];

void main() {
  test('no entries, no chips', () {
    expect(frequentAmounts(const []), isEmpty);
  });

  test('most frequent first', () {
    final entries = [
      spend(100),
      spend(250),
      spend(250),
      spend(40),
      spend(40),
      spend(40),
    ];
    expect(inRupees(frequentAmounts(entries)), [40, 250, 100]);
  });

  test('ties go to the more recently used amount', () {
    final entries = [
      spend(100, day: 3),
      spend(250, day: 1),
      spend(250, day: 2),
      spend(60, day: 5),
      spend(100, day: 4),
      spend(75, day: 2),
    ];
    // 100 and 250 twice each: 100 was used later. 60 and 75 once: 60 later.
    expect(inRupees(frequentAmounts(entries)), [100, 250, 60, 75]);
  });

  test('entries at the same moment tie-break by the later added', () {
    final entries = [spend(10), spend(20), spend(30)];
    expect(inRupees(frequentAmounts(entries)), [30, 20, 10]);
  });

  test('at most five chips', () {
    final entries = [for (var i = 1; i <= 8; i++) spend(i * 10, day: i)];
    expect(inRupees(frequentAmounts(entries)), [80, 70, 60, 50, 40]);
    expect(frequentAmounts(entries, limit: 2).length, 2);
  });

  test('income is not counted', () {
    final entries = [income(5000), income(5000), income(5000), spend(20)];
    expect(inRupees(frequentAmounts(entries)), [20]);
  });

  test('a new habit: ₹20 recorded most often becomes the first chip', () {
    final entries = [...seedEntries(DateTime(2026, 10, 5, 10))];
    expect(inRupees(frequentAmounts(entries)).contains(20), isFalse);
    entries
      ..add(spend(20, day: 5))
      ..add(spend(20, day: 5, minute: 1));
    expect(inRupees(frequentAmounts(entries)).first, 20);
  });

  test('seed data gives its five most recent amounts', () {
    final chips = frequentAmounts(seedEntries(DateTime(2026, 10, 5, 10)));
    expect(inRupees(chips), [650, 180, 450, 920, 280]);
  });
}
