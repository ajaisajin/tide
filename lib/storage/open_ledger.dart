/// Opening the saved, encrypted ledger.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'backup_exclusion.dart';
import 'drift/drift_ledger_store.dart';
import 'drift/encrypted_database.dart';
import 'drift/tide_database.dart';
import 'ledger_key.dart';
import 'open_ledger_result.dart';

export 'open_ledger_result.dart';

/// The directory, under the app's support directory, that holds the ledger.
/// It has the database to itself so that the whole directory, including any
/// journal file SQLite puts beside the database, can be excluded from backup.
const String ledgerDirectoryName = 'ledger';

/// The database's file name.
const String ledgerFileName = 'tide.sqlite';

/// Where the ledger is kept on this device:
/// `<application support>/ledger/tide.sqlite`.
Future<String> defaultLedgerPath() async {
  final support = await getApplicationSupportDirectory();
  final s = Platform.pathSeparator;
  return '${support.path}$s$ledgerDirectoryName$s$ledgerFileName';
}

/// Opens the ledger on this device, creating it on first use.
///
/// With no arguments this is what the app calls: the database at
/// [defaultLedgerPath], its key in the platform's secure storage. Tests pass
/// a [path] in a temporary directory and a fake [secrets].
///
/// The rules it keeps:
///
/// * A new key and a new database file are created only when no database
///   file exists.
/// * When a database file exists and cannot be read (no key, a wrong key, or
///   not a database) the result is [LedgerCannotBeOpened]. The file is not
///   written to, replaced, renamed or removed, and no key is created.
/// * Any other error gives [LedgerOpenFailed], again without changing
///   anything that existed.
///
/// It never throws.
Future<OpenLedgerResult> openLedger({
  String? path,
  SecretStore secrets = const PlatformSecretStore(),
  bool background = true,
}) async {
  try {
    final file = File(path ?? await defaultLedgerPath());
    final vault = LedgerKeyVault(secrets);
    final exists = file.existsSync();

    Uint8List? key;
    try {
      key = await vault.read();
    } on LedgerKeyMalformed {
      if (exists) {
        return const LedgerCannotBeOpened(LedgerUnreadableReason.keyMalformed);
      }
      // No database depends on whatever is stored; a new key replaces it.
    }

    if (exists) {
      if (key == null) {
        return const LedgerCannotBeOpened(LedgerUnreadableReason.keyMissing);
      }
      // Read-only, so an unreadable file is not touched.
      if (probeEncryptedFile(file, key) == ProbeResult.unreadable) {
        return const LedgerCannotBeOpened(
          LedgerUnreadableReason.notReadableWithKey,
        );
      }
    } else {
      // Key first: if the app dies between the two steps, the next launch
      // finds a key and no file, and carries on from there.
      key ??= await vault.create();
      file.parent.createSync(recursive: true);
    }
    await excludeFromBackup(file.parent.path);

    final database = TideDatabase(
      openEncryptedExecutor(file, key, background: background),
    );
    try {
      // The first statement opens the file, and for a new one creates the
      // tables. A wrong key would surface here if the probe had missed it.
      await database.customSelect('SELECT 1').get();
    } catch (error, stackTrace) {
      await _closeQuietly(database);
      if (exists && isUnreadableDatabaseError(error)) {
        return const LedgerCannotBeOpened(
          LedgerUnreadableReason.notReadableWithKey,
        );
      }
      return LedgerOpenFailed(error, stackTrace);
    }
    return LedgerOpened(DriftLedgerStore(database), created: !exists);
  } catch (error, stackTrace) {
    return LedgerOpenFailed(error, stackTrace);
  }
}

Future<void> _closeQuietly(TideDatabase database) async {
  try {
    await database.close();
  } catch (_) {
    // The open has already failed; that failure is the one reported.
  }
}
