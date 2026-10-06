import 'open_ledger.dart';

/// Opens the saved, encrypted ledger on this device. See [openLedger].
Future<OpenLedgerResult> openPlatformLedger() => openLedger();
