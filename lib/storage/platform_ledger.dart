/// Opens the ledger this platform keeps: the encrypted database where there
/// is a file system, and an in-memory one on the web, where nothing is saved.
library;

export 'platform_ledger_web.dart'
    if (dart.library.io) 'platform_ledger_io.dart';
