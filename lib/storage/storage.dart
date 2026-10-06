/// The parts of Tide's storage that work on every platform, the web
/// included: the store interface, the in-memory store, the outcomes of
/// opening a ledger, and [openPlatformLedger], which opens whichever ledger
/// this platform has.
///
/// The encrypted on-device store is in `device_ledger.dart`. It uses
/// `dart:io` and native SQLite, so import it only where the web is excluded.
library;

export 'ledger_store.dart';
export 'memory_ledger_store.dart';
export 'open_ledger_result.dart';
export 'platform_ledger.dart';
