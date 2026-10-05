/// Money formatting for Tide. Pure Dart: imports nothing from Flutter.
///
/// Every amount in the app is an integer number of paise ("minor units").
/// 100 paise = 1 rupee. Doubles are never used for money.
library;

/// Paise in one rupee.
const int paisePerRupee = 100;

/// The rupee sign, U+20B9.
const String rupeeSign = '₹';

/// A true minus sign, U+2212 (not the ASCII hyphen-minus).
const String minusSign = '−';

/// Converts whole rupees to paise.
int rupees(int wholeRupees) => wholeRupees * paisePerRupee;

/// Formats [amountMinor] (paise) as rupees with Indian digit grouping: the
/// last three digits of the rupee part, then groups of two.
///
///     formatRupees(15000000)  // ₹1,50,000
///     formatRupees(0)         // ₹0
///     formatRupees(-200000)   // −₹2,000
///
/// Whole-rupee amounts show no decimals. An amount with paise left over (which
/// cannot be entered in this version) shows exactly two decimals, e.g. 1250
/// paise is `₹12.50` and -5 paise is `−₹0.05`. Nothing is ever rounded: the
/// digits come from integer division only.
String formatRupees(int amountMinor) {
  final negative = amountMinor < 0;
  final magnitude = amountMinor.abs();
  final whole = magnitude ~/ paisePerRupee;
  final paise = magnitude % paisePerRupee;

  final buffer = StringBuffer();
  if (negative) buffer.write(minusSign);
  buffer
    ..write(rupeeSign)
    ..write(groupIndian(whole));
  if (paise != 0) {
    buffer
      ..write('.')
      ..write(paise.toString().padLeft(2, '0'));
  }
  return buffer.toString();
}

/// Groups the digits of a non-negative integer the Indian way:
/// `1234567` becomes `12,34,567`.
String groupIndian(int value) {
  assert(value >= 0, 'groupIndian takes a non-negative value');
  final digits = value.abs().toString();
  if (digits.length <= 3) return digits;

  final lastThree = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  groups.insert(0, rest);
  return '${groups.join(',')},$lastThree';
}
