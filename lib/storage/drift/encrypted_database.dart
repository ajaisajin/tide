/// Opening the ledger's SQLite file with AES-256 encryption.
///
/// The bundled SQLite is SQLite3 Multiple Ciphers (see `hooks:` in
/// pubspec.yaml). Its default cipher is ChaCha20, so the AES-256 SQLCipher
/// scheme is chosen on every open, before the key is given. These settings
/// are fixed for the life of a database file: changing any of them means
/// re-encrypting it.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:sqlite3/sqlite3.dart' as raw;

/// The length of the database key: 32 bytes, for AES-256.
const int ledgerKeyLength = 32;

/// SQLite's "file is not a database" result. A missing or wrong key shows up
/// as this, on the first statement that reads the file.
const int sqliteNotADatabase = 26;

/// SQLite's "database disk image is malformed" result.
const int sqliteCorrupt = 11;

/// [key] as 64 lower-case hex digits. Throws an [ArgumentError] unless it is
/// exactly 32 bytes.
String ledgerKeyHex(Uint8List key) {
  if (key.length != ledgerKeyLength) {
    throw ArgumentError('The ledger key must be $ledgerKeyLength bytes');
  }
  final buffer = StringBuffer();
  for (final byte in key) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// Selects the cipher and gives the key on a newly opened connection.
///
/// In order: the SQLCipher scheme (AES-256-CBC with an HMAC-SHA512 tag per
/// page), its version-4 file layout with the whole header encrypted
/// (`legacy = 4`), then the key as 32 raw bytes with no passphrase
/// stretching. A wrong key is not noticed here; the first read fails with
/// result 26.
void applyLedgerCipher(raw.Database db, String keyHex) {
  // A SQLite without encryption support would ignore `PRAGMA key` and write
  // plain text. It also returns nothing for `PRAGMA cipher`.
  if (db.select('PRAGMA cipher').isEmpty) {
    throw StateError('SQLite was built without encryption');
  }
  db.execute("PRAGMA cipher = 'sqlcipher'");
  db.execute('PRAGMA legacy = 4');
  db.execute('PRAGMA key = "x\'$keyHex\'"');
}

// A top-level function so the closure it returns captures the hex string and
// nothing else: it is sent to the database's background isolate.
void Function(raw.Database) _setupFor(String keyHex) =>
    (db) => applyLedgerCipher(db, keyHex);

/// A Drift executor for the encrypted database at [file], opened with the
/// 32-byte [key]. The file is created if it does not exist.
///
/// With [background] the database runs on its own isolate, which is what the
/// app uses; without it, on the calling isolate.
QueryExecutor openEncryptedExecutor(
  File file,
  Uint8List key, {
  bool background = true,
}) {
  final setup = _setupFor(ledgerKeyHex(key));
  return background
      ? NativeDatabase.createInBackground(file, setup: setup)
      : NativeDatabase(file, setup: setup);
}

/// What [probeEncryptedFile] found.
enum ProbeResult {
  /// The file opens and reads with the key.
  readable,

  /// The file does not read with the key: the key is wrong, or the file is
  /// not one of our databases, or it is damaged.
  unreadable,
}

/// Checks whether the existing [file] reads with [key], without changing it.
///
/// The file is opened read-only, so nothing is created or written whatever
/// the outcome. Errors other than "not a database" and "malformed" are
/// rethrown.
ProbeResult probeEncryptedFile(File file, Uint8List key) {
  final keyHex = ledgerKeyHex(key);
  final db = raw.sqlite3.open(file.path, mode: raw.OpenMode.readOnly);
  try {
    applyLedgerCipher(db, keyHex);
    db.select('SELECT count(*) FROM sqlite_master');
    return ProbeResult.readable;
  } on raw.SqliteException catch (e) {
    if (isUnreadableDatabaseError(e)) return ProbeResult.unreadable;
    rethrow;
  } finally {
    db.close();
  }
}

/// Whether [error] is SQLite saying the file cannot be read as a database
/// with the key given, including when Drift passes the error on from its
/// background isolate.
bool isUnreadableDatabaseError(Object error) {
  Object cause = error;
  if (cause is DriftRemoteException) cause = cause.remoteCause;
  if (cause is raw.SqliteException) {
    final code = cause.resultCode;
    return code == sqliteNotADatabase || code == sqliteCorrupt;
  }
  return false;
}
