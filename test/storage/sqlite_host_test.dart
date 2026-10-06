// Smoke tests for the SQLite library that `flutter test` loads on the host.
//
// The build hook of package:sqlite3 bundles the same SQLite3 Multiple Ciphers
// build for the host as for Android (see `hooks:` in pubspec.yaml), so Drift
// tests need no system SQLite and no emulator.
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

class _BareDatabase extends GeneratedDatabase {
  _BareDatabase(super.executor);

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 1;
}

void main() {
  test('Drift opens an unencrypted in-memory database on the host', () async {
    final db = _BareDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.customStatement(
      'CREATE TABLE notes (id INTEGER PRIMARY KEY, note TEXT NOT NULL)',
    );
    await db.customStatement('INSERT INTO notes (note) VALUES (?)', ['hello']);

    final row = await db.customSelect('SELECT note FROM notes').getSingle();
    expect(row.read<String>('note'), 'hello');
  });

  test('the bundled SQLite is the encrypted build and offers the AES-256 '
      'SQLCipher scheme', () {
    final dir = Directory.systemTemp.createTempSync('tide_sqlite_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/encrypted.sqlite';
    final key = List.filled(32, '5a').join();

    raw.Database open({required bool withKey}) {
      final db = raw.sqlite3.open(path);
      db.execute("PRAGMA cipher = 'sqlcipher'");
      if (withKey) db.execute('PRAGMA key = "x\'$key\'"');
      return db;
    }

    final created = open(withKey: true);
    expect(created.select('PRAGMA cipher').single.values.single, 'sqlcipher');
    created
      ..execute('CREATE TABLE notes (note TEXT NOT NULL)')
      ..execute("INSERT INTO notes VALUES ('plain text marker')")
      ..close();

    final bytes = File(path).readAsBytesSync();
    expect(String.fromCharCodes(bytes), isNot(contains('SQLite format 3')));
    expect(String.fromCharCodes(bytes), isNot(contains('plain text marker')));

    final reopened = open(withKey: true);
    expect(
      reopened.select('SELECT note FROM notes').single['note'],
      'plain text marker',
    );
    reopened.close();

    final keyless = open(withKey: false);
    addTearDown(keyless.close);
    expect(
      () => keyless.select('SELECT note FROM notes'),
      throwsA(isA<raw.SqliteException>()),
    );
  });
}
