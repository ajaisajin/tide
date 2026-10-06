/// The outcomes of opening the saved ledger. Pure Dart, so the start-up code
/// can name them on every platform, the web included.
library;

import 'ledger_store.dart';

/// The outcome of opening the ledger. Exactly one of [LedgerOpened],
/// [LedgerCannotBeOpened] and [LedgerOpenFailed].
sealed class OpenLedgerResult {
  const OpenLedgerResult();
}

/// The ledger is open. [store] is ready to use; close it when done.
final class LedgerOpened extends OpenLedgerResult {
  const LedgerOpened(this.store, {required this.created});

  final LedgerStore store;

  /// True when there was no database file and this open made one.
  final bool created;
}

/// Why saved data could not be opened.
enum LedgerUnreadableReason {
  /// The database file exists but secure storage holds no key for it.
  keyMissing,

  /// Something is stored where the key should be, but it is not a key.
  keyMalformed,

  /// The file does not read with the stored key: the key is the wrong one,
  /// or the file is not a Tide database, or it is damaged.
  notReadableWithKey,
}

/// Saved data exists but cannot be opened. The file has been left exactly as
/// it was and no key has been created. The app must say so and offer Retry;
/// it must not show setup or an empty ledger.
final class LedgerCannotBeOpened extends OpenLedgerResult {
  const LedgerCannotBeOpened(this.reason);

  final LedgerUnreadableReason reason;

  @override
  String toString() => 'LedgerCannotBeOpened(${reason.name})';
}

/// Opening failed for some other reason, such as secure storage or the file
/// system reporting an error. Nothing existing was changed. Retry may work.
final class LedgerOpenFailed extends OpenLedgerResult {
  const LedgerOpenFailed(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;

  @override
  String toString() => 'LedgerOpenFailed($error)';
}
