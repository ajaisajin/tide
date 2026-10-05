import 'package:flutter_test/flutter_test.dart';
import 'package:tide/log/amount.dart';

void main() {
  AmountEntry typed(
    List<int> digits, [
    AmountEntry from = AmountEntry.initial,
  ]) => digits.fold(from, (a, d) => a.pressDigit(d));

  group('amount range', () {
    test('starts at ₹0, unset, with no method', () {
      expect(AmountEntry.initial.rupees, 0);
      expect(AmountEntry.initial.isSet, isFalse);
      expect(AmountEntry.initial.method, isNull);
    });

    test('upper bound: raising above ₹9,99,999 stays at ₹9,99,999', () {
      final top = typed([9, 9, 9, 9, 9, 9]);
      expect(top.rupees, 999999);
      expect(top.stepByRing(10).rupees, 999999);
      expect(top.stepByRing(1000).rupees, 999999);
      expect(top.pressDigit(9).rupees, 999999);
      // A step that would pass the bound lands on it.
      expect(typed([9, 9, 9, 9, 9, 5]).stepByRing(10).rupees, 999999);
      expect(const AmountEntry().setFromChip(5000000).rupees, 999999);
      expect(clampAmount(1000000), maxAmountRupees);
    });

    test('lower bound: lowering below ₹0 stays at ₹0', () {
      expect(AmountEntry.initial.stepByRing(-10).rupees, 0);
      expect(typed([5]).stepByRing(-10).rupees, 0);
      expect(typed([5]).stepByRing(-1000).rupees, 0);
      expect(AmountEntry.initial.pressDelete().rupees, 0);
      expect(clampAmount(-1), 0);
    });

    test('₹1 is the least amount that can be filed', () {
      expect(typed([0]).isSet, isFalse);
      expect(typed([1]).isSet, isTrue);
    });
  });

  group('number pad', () {
    test('3 then 7 gives ₹37', () {
      expect(typed([3, 7]).rupees, 37);
    });

    test('delete on ₹1,850 gives ₹185', () {
      expect(typed([1, 8, 5, 0]).pressDelete().rupees, 185);
    });

    test('any amount in the range can be typed', () {
      expect(typed([1]).rupees, 1);
      expect(typed([9, 9, 9, 9, 9, 9]).rupees, 999999);
      expect(typed([1, 0, 0, 0, 0, 0]).rupees, 100000);
    });

    test('a digit that would pass ₹9,99,999 is ignored', () {
      final six = typed([1, 2, 3, 4, 5, 6]);
      expect(six.pressDigit(7), six);
    });

    test('the first digit replaces an amount set by a chip', () {
      final chip = AmountEntry.initial.setFromChip(250);
      expect(chip.rupees, 250);
      expect(typed([3, 7], chip).rupees, 37);
    });

    test('the first digit replaces an amount set by the ring', () {
      final ring = AmountEntry.initial.stepByRing(100).stepByRing(100);
      expect(ring.rupees, 200);
      expect(typed([4], ring).rupees, 4);
      expect(typed([4, 5], ring).rupees, 45);
    });

    test('digits after delete append to what is left', () {
      final chip = AmountEntry.initial.setFromChip(250);
      expect(chip.pressDelete().pressDigit(3).rupees, 253);
    });

    test('leading zeros do nothing', () {
      expect(typed([0, 0, 5]).rupees, 5);
    });
  });

  group('ring steps', () {
    test('step by the size given, up and down', () {
      final a = AmountEntry.initial.setFromChip(500);
      expect(a.stepByRing(10).rupees, 510);
      expect(a.stepByRing(100).rupees, 600);
      expect(a.stepByRing(1000).rupees, 1000);
      expect(a.stepByRing(-10).rupees, 490);
      expect(a.stepByRing(-100).rupees, 400);
      expect(a.setFromChip(3000).stepByRing(-1000).rupees, 2000);
    });

    test('land on multiples of the step size', () {
      final odd = AmountEntry.initial.setFromChip(37);
      expect(odd.stepByRing(10).rupees, 40);
      expect(odd.stepByRing(-10).rupees, 30);
      final mixed = AmountEntry.initial.setFromChip(6110);
      expect(mixed.stepByRing(1000).rupees, 7000);
      expect(mixed.stepByRing(-1000).rupees, 6000);
      expect(mixed.stepByRing(100).rupees, 6200);
    });
  });

  group('last-used method', () {
    test('follows whichever control changed the amount last', () {
      var a = AmountEntry.initial.pressDigit(5);
      expect(a.method, AmountMethod.pad);
      a = a.setFromChip(250);
      expect(a.method, AmountMethod.chips);
      a = a.stepByRing(10);
      expect(a.method, AmountMethod.ring);
      a = a.pressDelete();
      expect(a.method, AmountMethod.pad);
    });

    test('a ring step that cannot move the amount does not count', () {
      final a = AmountEntry.initial.stepByRing(-10);
      expect(a.method, isNull);
      expect(a, AmountEntry.initial);
    });
  });
}
