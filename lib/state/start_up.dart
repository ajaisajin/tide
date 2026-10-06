import '../storage/storage.dart';
import 'clock.dart';
import 'ledger.dart';

/// How start-up ended: with a ledger and its starting data, or without.
sealed class StartResult {
  const StartResult();
}

/// The ledger is open and what the first frame needs has been read.
final class Started extends StartResult {
  const Started(this.store, this.start);

  final LedgerStore store;
  final LedgerStart start;
}

/// The ledger could not be opened or read. Nothing saved was changed. The
/// app shows the error screen with Retry; it must not show setup or an empty
/// ledger.
final class StartFailed extends StartResult {
  const StartFailed(this.cause);

  /// A [LedgerCannotBeOpened] or a [LedgerOpenFailed].
  final OpenLedgerResult cause;
}

/// Opens the ledger with [open] and reads the starting data for the moment
/// [clock] gives. Never throws. Retry is this same call again.
Future<StartResult> startUp({
  Future<OpenLedgerResult> Function() open = openPlatformLedger,
  Clock clock = DateTime.now,
}) async {
  final OpenLedgerResult opened;
  try {
    opened = await open();
  } catch (error, stackTrace) {
    return StartFailed(LedgerOpenFailed(error, stackTrace));
  }
  if (opened is! LedgerOpened) return StartFailed(opened);
  try {
    return Started(opened.store, await loadLedgerStart(opened.store, clock()));
  } catch (error, stackTrace) {
    // Data that opens but does not read is not "no data": report it, and
    // leave the file for the next try.
    try {
      await opened.store.close();
    } catch (_) {
      // The read failure is the one reported.
    }
    return StartFailed(LedgerOpenFailed(error, stackTrace));
  }
}
