/// The rules for the amount being entered in the log flow. Pure Dart.
library;

/// The largest amount an entry may have, in whole rupees: ₹9,99,999.
const int maxAmountRupees = 999999;

/// The control that changed the amount.
enum AmountMethod {
  pad('Pad'),
  ring('Ring'),
  chips('Chips');

  const AmountMethod(this.label);

  final String label;
}

/// Keeps [rupees] within ₹0 to ₹9,99,999.
int clampAmount(int rupees) =>
    rupees < 0 ? 0 : (rupees > maxAmountRupees ? maxAmountRupees : rupees);

/// The amount being entered: whole rupees from 0 (unset) to
/// [maxAmountRupees], the control that changed it last, and whether the next
/// pad digit starts a new number.
class AmountEntry {
  const AmountEntry({
    this.rupees = 0,
    this.method,
    this.nextDigitReplaces = true,
  });

  /// ₹0, as the log flow opens.
  static const initial = AmountEntry();

  final int rupees;

  /// The control that changed the amount last; null while nothing has.
  final AmountMethod? method;

  /// True when the log flow has just opened, or a chip or the ring set the
  /// amount: the next digit replaces the amount rather than extending it.
  final bool nextDigitReplaces;

  /// An entry can be filed only with an amount of at least ₹1.
  bool get isSet => rupees >= 1;

  /// A pad digit, 0 to 9. The first one replaces the amount, later ones
  /// append, and one that would pass [maxAmountRupees] is ignored.
  AmountEntry pressDigit(int digit) {
    assert(digit >= 0 && digit <= 9, 'a pad digit is 0 to 9');
    if (nextDigitReplaces) {
      return AmountEntry(
        rupees: digit,
        method: AmountMethod.pad,
        nextDigitReplaces: false,
      );
    }
    final next = rupees * 10 + digit;
    if (next > maxAmountRupees) return this;
    return AmountEntry(
      rupees: next,
      method: AmountMethod.pad,
      nextDigitReplaces: false,
    );
  }

  /// The pad's delete key: drops the last digit. Digits pressed afterwards
  /// append to what is left.
  AmountEntry pressDelete() => AmountEntry(
    rupees: rupees ~/ 10,
    method: AmountMethod.pad,
    nextDigitReplaces: false,
  );

  /// A chip: sets the amount outright.
  AmountEntry setFromChip(int value) => AmountEntry(
    rupees: clampAmount(value),
    method: AmountMethod.chips,
    nextDigitReplaces: true,
  );

  /// One ring step of [delta] rupees, up or down, kept within the range.
  ///
  /// The amount moves to the next multiple of the step size in that
  /// direction, so ₹37 stepped up by ₹10 is ₹40 and ₹6,110 stepped up by
  /// ₹1,000 is ₹7,000: a spin always lands on round figures. A step that
  /// cannot move the amount (already at a bound) changes nothing.
  AmountEntry stepByRing(int delta) {
    if (delta == 0) return this;
    final step = delta.abs();
    final over = rupees % step;
    final target = delta > 0
        ? rupees - over + step
        : (over == 0 ? rupees - step : rupees - over);
    final next = clampAmount(target);
    if (next == rupees) return this;
    return AmountEntry(
      rupees: next,
      method: AmountMethod.ring,
      nextDigitReplaces: true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AmountEntry &&
      other.rupees == rupees &&
      other.method == method &&
      other.nextDigitReplaces == nextDigitReplaces;

  @override
  int get hashCode => Object.hash(rupees, method, nextDigitReplaces);

  @override
  String toString() =>
      'AmountEntry($rupees, ${method?.name}, replace: $nextDigitReplaces)';
}
