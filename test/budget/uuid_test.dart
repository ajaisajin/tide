import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tide/budget/budget.dart';

/// A "random" source that always returns the largest value, to force the
/// counter to roll over.
class _MaxRandom implements Random {
  @override
  int nextInt(int max) => max - 1;
  @override
  bool nextBool() => true;
  @override
  double nextDouble() => 0.999;
}

void main() {
  final layout = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  test('standard textual format with version 7 and the RFC variant', () {
    for (var i = 0; i < 2000; i++) {
      final id = newUuidV7();
      expect(id.length, 36);
      expect(layout.hasMatch(id), isTrue, reason: id);
      expect(id[14], '7', reason: 'version nibble');
      expect('89ab'.contains(id[19]), isTrue, reason: 'variant bits 10');
      expect(isUuidV7(id), isTrue);
    }
  });

  test('isUuidV7 rejects other versions, variants and shapes', () {
    expect(isUuidV7('019a2b3c-4d5e-7f01-8a2b-3c4d5e6f7a8b'), isTrue);
    expect(isUuidV7('019a2b3c-4d5e-4f01-8a2b-3c4d5e6f7a8b'), isFalse);
    expect(isUuidV7('019a2b3c-4d5e-7f01-ca2b-3c4d5e6f7a8b'), isFalse);
    expect(isUuidV7('019A2B3C-4D5E-7F01-8A2B-3C4D5E6F7A8B'), isFalse);
    expect(isUuidV7('seed-1'), isFalse);
    expect(() => uuidV7Millis('seed-1'), throwsFormatException);
  });

  test('ids are unique', () {
    final ids = {for (var i = 0; i < 20000; i++) newUuidV7()};
    expect(ids.length, 20000);
  });

  test('ids sort in the order they were made, even within one '
      'millisecond', () {
    final ids = [for (var i = 0; i < 20000; i++) newUuidV7()];
    final sorted = [...ids]..sort();
    expect(sorted, ids);
  });

  test('the leading 48 bits are the Unix time in milliseconds', () {
    final moment = DateTime.utc(2026, 10, 5, 12, 30, 15, 250);
    final id = UuidV7Generator(clock: () => moment).next();
    expect(uuidV7Millis(id), moment.millisecondsSinceEpoch);
    // 1 791 203 415 250 ms is 0x01a10b7b08d2.
    expect(
      id.substring(0, 13).replaceAll('-', ''),
      moment.millisecondsSinceEpoch.toRadixString(16).padLeft(12, '0'),
    );

    final before = DateTime.now().millisecondsSinceEpoch;
    final live = uuidV7Millis(newUuidV7());
    final after = DateTime.now().millisecondsSinceEpoch;
    expect(live, inInclusiveRange(before, after));
  });

  test('later clock readings give later ids', () {
    var now = DateTime.utc(2026, 10, 5);
    final generator = UuidV7Generator(clock: () => now);
    final ids = <String>[];
    for (var i = 0; i < 500; i++) {
      ids.add(generator.next());
      now = now.add(const Duration(milliseconds: 7));
    }
    expect([...ids]..sort(), ids);
    expect(ids.toSet().length, ids.length);
  });

  test('a clock that stands still or steps back still gives rising, '
      'distinct ids', () {
    var now = DateTime.utc(2026, 10, 5, 10);
    final generator = UuidV7Generator(clock: () => now, random: Random(1));
    final ids = <String>[generator.next(), generator.next()];
    now = now.subtract(const Duration(seconds: 30));
    ids
      ..add(generator.next())
      ..add(generator.next());
    expect([...ids]..sort(), ids);
    expect(ids.toSet().length, 4);
    expect(ids.every(isUuidV7), isTrue);
    // The time field never goes backwards.
    expect(uuidV7Millis(ids[2]), uuidV7Millis(ids[0]));
  });

  test('when the random part rolls over, the next millisecond is used and '
      'the format holds', () {
    final now = DateTime.utc(2026, 10, 5, 10);
    final generator = UuidV7Generator(clock: () => now, random: _MaxRandom());
    final first = generator.next();
    final second = generator.next();
    expect(first.substring(14), '7fff-bfff-ffffffffffff');
    expect(isUuidV7(second), isTrue);
    expect(second.compareTo(first), greaterThan(0));
    expect(uuidV7Millis(second), uuidV7Millis(first) + 1);
  });

  test('different generators do not repeat each other', () {
    final now = DateTime.utc(2026, 10, 5);
    final a = UuidV7Generator(clock: () => now);
    final b = UuidV7Generator(clock: () => now);
    final ids = {
      for (var i = 0; i < 1000; i++) ...[a.next(), b.next()],
    };
    expect(ids.length, 2000);
  });
}
