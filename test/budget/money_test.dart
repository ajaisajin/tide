import 'package:flutter_test/flutter_test.dart';
import 'package:tide/budget/budget.dart';

void main() {
  group('Exact amounts in Indian format', () {
    test('Lakh grouping: one lakh fifty thousand reads ₹1,50,000', () {
      expect(formatRupees(rupees(150000)), '₹1,50,000');
    });

    test('zero reads ₹0', () {
      expect(formatRupees(0), '₹0');
    });

    test('a negative amount leads with a true minus sign', () {
      expect(formatRupees(rupees(-2000)), '−₹2,000');
      expect(formatRupees(rupees(-2000)).codeUnitAt(0), 0x2212);
    });

    test('amounts of seven digits and more group in twos', () {
      expect(formatRupees(rupees(1234567)), '₹12,34,567');
      expect(formatRupees(rupees(123456789)), '₹12,34,56,789');
      expect(formatRupees(rupees(10000000)), '₹1,00,00,000');
    });

    test('small amounts and each group boundary', () {
      expect(formatRupees(rupees(7)), '₹7');
      expect(formatRupees(rupees(999)), '₹999');
      expect(formatRupees(rupees(1000)), '₹1,000');
      expect(formatRupees(rupees(13601)), '₹13,601');
      expect(formatRupees(rupees(99999)), '₹99,999');
      expect(formatRupees(rupees(100000)), '₹1,00,000');
      expect(formatRupees(rupees(999999)), '₹9,99,999');
    });

    test('non-whole paise show two exact decimals, never rounded', () {
      expect(formatRupees(1250), '₹12.50');
      expect(formatRupees(5), '₹0.05');
      expect(formatRupees(99), '₹0.99');
      expect(formatRupees(15000001), '₹1,50,000.01');
      expect(formatRupees(-5), '−₹0.05');
      expect(formatRupees(-199999), '−₹1,999.99');
    });

    test('Repeated small entries: ten ₹37 expenses leave exactly ₹29,630', () {
      final now = DateTime(2026, 10, 5);
      final entries = [
        for (var i = 0; i < 10; i++)
          Entry(
            id: 'e$i',
            type: EntryType.expense,
            amountMinor: rupees(37),
            categoryId: 'food',
            occurredAt: now,
          ),
      ];
      final position = monthlyPosition(
        budgetMinor: rupees(30000),
        entries: entries,
        now: now,
      );
      expect(position.remainingMinor, 2963000);
      expect(formatRupees(position.remainingMinor), '₹29,630');
    });
  });
}
