import 'memory_ledger_store.dart';
import 'open_ledger_result.dart';

/// The web has no saved ledger: every visit starts with an empty one held in
/// memory, which is gone when the tab closes.
Future<OpenLedgerResult> openPlatformLedger() async =>
    LedgerOpened(MemoryLedgerStore(), created: true);
