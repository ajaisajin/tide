/// UUID version 7 identifiers (RFC 9562). Pure Dart: imports nothing from
/// Flutter, and avoids 64-bit integer tricks so it also runs on the web.
library;

import 'dart:math';

/// Makes UUID v7 strings: 48 bits of Unix time in milliseconds, then the
/// version, then 74 random bits around the variant marker.
///
/// Ids from one generator always sort (as text) in the order they were made.
/// Within one millisecond, or if the clock steps backwards, the previous
/// time is kept and the random part is counted upwards instead of drawn
/// afresh (RFC 9562 section 6.2, method 2).
class UuidV7Generator {
  /// [random] defaults to the platform's secure source. [clock] defaults to
  /// `DateTime.now`; tests pass their own.
  UuidV7Generator({Random? random, DateTime Function()? clock})
    : _random = random ?? Random.secure(),
      _clock = clock ?? DateTime.now;

  final Random _random;
  final DateTime Function() _clock;

  int _lastMillis = -1;

  // The 74 random bits, held as 12 + 30 + 32 so each fits a web integer.
  int _a = 0;
  int _b = 0;
  int _c = 0;

  static const int _maxA = 0x1000;
  static const int _maxB = 0x40000000;
  static const int _maxC = 0x100000000;

  /// The next id, in the standard 8-4-4-4-12 lower-case form.
  String next() {
    final now = _clock().millisecondsSinceEpoch;
    if (now > _lastMillis) {
      _lastMillis = now;
      _draw();
    } else if (!_increment()) {
      // All 74 bits rolled over within one millisecond: borrow the next one.
      _lastMillis++;
      _draw();
    }
    return _format(_lastMillis, _a, _b, _c);
  }

  void _draw() {
    _a = _random.nextInt(_maxA);
    _b = _random.nextInt(_maxB);
    _c = _random.nextInt(_maxC);
  }

  /// Adds one to the random part. False if it overflowed.
  bool _increment() {
    _c++;
    if (_c < _maxC) return true;
    _c = 0;
    _b++;
    if (_b < _maxB) return true;
    _b = 0;
    _a++;
    if (_a < _maxA) return true;
    _a = 0;
    return false;
  }

  static String _format(int millis, int a, int b, int c) {
    // 48-bit timestamp as 8 + 4 hex digits, split by division so that no
    // intermediate value needs more than 53 bits.
    final timeHigh = millis ~/ 0x10000;
    final timeLow = millis % 0x10000;
    // Variant bits "10", then the top 14 of b's 30 bits.
    final variantAndB = 0x8000 | (b ~/ 0x10000);
    final bLow = b % 0x10000;
    return '${_hex(timeHigh, 8)}-${_hex(timeLow, 4)}-7${_hex(a, 3)}-'
        '${_hex(variantAndB, 4)}-${_hex(bLow, 4)}${_hex(c, 8)}';
  }

  static String _hex(int value, int width) =>
      value.toRadixString(16).padLeft(width, '0');
}

final UuidV7Generator _shared = UuidV7Generator();

/// A new UUID v7 from the app-wide generator, for example
/// `019a2b3c-4d5e-7f01-8a2b-3c4d5e6f7a8b`.
String newUuidV7() => _shared.next();

final RegExp _uuidV7Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// Whether [text] is a lower-case UUID with version 7 and the RFC variant.
bool isUuidV7(String text) => _uuidV7Pattern.hasMatch(text);

/// The moment encoded in the UUID v7 [id], as milliseconds since the Unix
/// epoch. Throws a [FormatException] when [id] is not a UUID v7.
int uuidV7Millis(String id) {
  if (!isUuidV7(id)) throw FormatException('Not a UUID v7', id);
  return int.parse(id.substring(0, 8), radix: 16) * 0x10000 +
      int.parse(id.substring(9, 13), radix: 16);
}
