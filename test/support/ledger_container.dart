import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tide/state/clock.dart';
import 'package:tide/state/ledger.dart';
import 'package:tide/storage/storage.dart';

/// A provider container on [store], loaded as `main()` loads it, for tests
/// without widgets. Left out, [store] is an in-memory one holding the sample
/// month for the clock's date. The clock is [clock], or fixed at [now].
Future<ProviderContainer> ledgerContainer({
  required DateTime now,
  Clock? clock,
  LedgerStore? store,
  List<Override> overrides = const [],
}) async {
  // The "today" notifier listens for the app returning to the foreground.
  TestWidgetsFlutterBinding.ensureInitialized();
  final start = clock?.call() ?? now;
  final ledger = store ?? MemoryLedgerStore.sampleMonth(start);
  return ProviderContainer.test(
    overrides: [
      ...ledgerOverrides(ledger, await loadLedgerStart(ledger, start)),
      clockProvider.overrideWithValue(clock ?? () => now),
      ...overrides,
    ],
  );
}
