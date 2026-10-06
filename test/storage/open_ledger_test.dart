// The "open ledger" entry point on the development machine, with a fake key
// store and real encrypted files in a temporary directory.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:tide/budget/budget.dart';
import 'package:tide/storage/device_ledger.dart';

import '../support/fake_secret_store.dart';

const _keyName = LedgerKeyVault.defaultName;

/// Everything in [dir]: path to (bytes, modified time).
Map<String, (List<int>, DateTime)> _snapshot(Directory dir) => {
  for (final f in dir.listSync(recursive: true).whereType<File>())
    f.path: (f.readAsBytesSync().toList(), f.lastModifiedSync()),
};

void _expectUnchanged(
  Directory dir,
  Map<String, (List<int>, DateTime)> before,
) {
  final after = _snapshot(dir);
  expect(after.keys.toSet(), before.keys.toSet(), reason: 'same files');
  for (final path in before.keys) {
    expect(after[path]!.$1, before[path]!.$1, reason: 'bytes of $path');
    expect(after[path]!.$2, before[path]!.$2, reason: 'mtime of $path');
  }
}

Entry _entry(String id, int rupeeAmount) => Entry(
  id: id,
  type: EntryType.expense,
  amountMinor: rupees(rupeeAmount),
  categoryId: 'food',
  note: 'Paneer tikka lunch',
  occurredAt: DateTime(2026, 10, 5, 13),
);

void main() {
  late Directory dir;
  late String path;
  const oct = YearMonth(2026, 10);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tide_open_test');
    path = '${dir.path}/ledger/tide.sqlite';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<OpenLedgerResult> open(
    FakeSecretStore secrets, {
    bool background = false,
  }) => openLedger(path: path, secrets: secrets, background: background);

  /// Creates a ledger with one entry and a budget, closes it, and returns
  /// the secrets that open it.
  Future<FakeSecretStore> createLedger() async {
    final secrets = FakeSecretStore();
    final result = await open(secrets) as LedgerOpened;
    await result.store.insertEntry(_entry('e1', 250));
    await result.store.setBudget(oct, rupees(30000));
    await result.store.close();
    return secrets;
  }

  group('opened', () {
    test(
      'first open creates a 32-byte key, the directory and the file',
      () async {
        final secrets = FakeSecretStore();
        final result = await open(secrets);
        expect(result, isA<LedgerOpened>());
        result as LedgerOpened;
        addTearDown(result.store.close);
        expect(result.created, isTrue);
        expect(result.store, isA<DriftLedgerStore>());

        expect(secrets.values.keys, [_keyName]);
        expect(secrets.values[_keyName], matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(secrets.writes, 1);
        expect(File(path).existsSync(), isTrue);
        expect(await result.store.hasAnyBudget(), isFalse);
      },
    );

    test(
      'a second open reuses the key and reads back what was saved',
      () async {
        final secrets = await createLedger();
        final keyBefore = secrets.values[_keyName];

        final result = await open(secrets);
        expect(result, isA<LedgerOpened>());
        result as LedgerOpened;
        addTearDown(result.store.close);
        expect(result.created, isFalse);
        expect(secrets.values[_keyName], keyBefore);
        expect(secrets.writes, 1, reason: 'the key is written once, ever');
        expect(await result.store.entriesForMonth(oct), [_entry('e1', 250)]);
        expect(await result.store.budgetFor(oct), rupees(30000));
      },
    );

    test('works on a background isolate too, as the app runs it', () async {
      final secrets = FakeSecretStore();
      final first = await open(secrets, background: true) as LedgerOpened;
      await first.store.insertEntry(_entry('e1', 250));
      await first.store.close();
      final second = await open(secrets, background: true);
      expect(second, isA<LedgerOpened>());
      second as LedgerOpened;
      expect(await second.store.entriesForMonth(oct), [_entry('e1', 250)]);
      await second.store.close();
    });

    test('a key with no file (the app died between the two steps) is reused, '
        'not replaced', () async {
      final existing = List.filled(32, 'a7').join();
      final secrets = FakeSecretStore({_keyName: existing});
      final result = await open(secrets) as LedgerOpened;
      await result.store.close();
      expect(result.created, isTrue);
      expect(secrets.values[_keyName], existing);
      expect(secrets.writes, 0);
      // And the file really is under that key.
      final key = Uint8List.fromList(List.filled(32, 0xa7));
      expect(probeEncryptedFile(File(path), key), ProbeResult.readable);
    });

    test(
      'a malformed stored key with no file is replaced by a new key',
      () async {
        final secrets = FakeSecretStore({_keyName: 'not a key'});
        final result = await open(secrets);
        expect(result, isA<LedgerOpened>());
        await (result as LedgerOpened).store.close();
        expect(secrets.values[_keyName], matches(RegExp(r'^[0-9a-f]{64}$')));
      },
    );

    test('the file is encrypted: no SQLite header, no plain text, and the '
        'first 16 bytes are not plain either', () async {
      await createLedger();
      final bytes = File(path).readAsBytesSync();
      final text = String.fromCharCodes(bytes);
      expect(bytes.length, greaterThan(4096));
      expect(text, isNot(contains('SQLite format 3')));
      for (final plain in [
        'Paneer',
        'tikka',
        'entries',
        'food',
        'expense',
        '2026-10',
        'CREATE',
      ]) {
        expect(text, isNot(contains(plain)), reason: plain);
      }
      // With legacy = 4 the header is a random salt, different per file.
      final secondDir = Directory('${dir.path}/second')..createSync();
      final other = await openLedger(
        path: '${secondDir.path}/tide.sqlite',
        secrets: FakeSecretStore(),
        background: false,
      );
      await (other as LedgerOpened).store.close();
      final otherBytes = File(
        '${secondDir.path}/tide.sqlite',
      ).readAsBytesSync();
      expect(otherBytes.sublist(0, 16), isNot(bytes.sublist(0, 16)));
      // Bytes 16 to 23, plain in the non-legacy layout (page size 4096 is
      // 0x10 0x00), are encrypted too.
      expect(bytes.sublist(16, 18), isNot([0x10, 0x00]));
    });

    test('the cipher in effect is sqlcipher with legacy 4, and other schemes '
        'or a plain open cannot read the file', () async {
      final secrets = await createLedger();
      final keyHex = secrets.values[_keyName]!;

      List<Object?> attempt(List<String> pragmas) {
        final db = raw.sqlite3.open(path, mode: raw.OpenMode.readOnly);
        try {
          for (final p in pragmas) {
            db.execute(p);
          }
          db.select('SELECT count(*) FROM entries');
          final out = <Object?>[
            for (final name in [
              'cipher',
              'legacy',
              'legacy_page_size',
              'hmac_use',
              'kdf_iter',
            ])
              db.select('PRAGMA $name').single.values.single,
          ];
          return out;
        } finally {
          db.close();
        }
      }

      final key = 'PRAGMA key = "x\'$keyHex\'"';
      expect(
        attempt(["PRAGMA cipher = 'sqlcipher'", 'PRAGMA legacy = 4', key]),
        ['sqlcipher', '4', '4096', '1', '256000'],
      );
      final refused = throwsA(
        isA<raw.SqliteException>().having((e) => e.resultCode, 'code', 26),
      );
      expect(() => attempt([]), refused, reason: 'no key');
      expect(
        () => attempt([key]),
        refused,
        reason: 'default cipher (chacha20)',
      );
      expect(
        () => attempt(["PRAGMA cipher = 'sqlcipher'", key]),
        refused,
        reason: 'sqlcipher without legacy = 4',
      );
      expect(
        () => attempt(["PRAGMA cipher = 'aes256cbc'", key]),
        refused,
        reason: 'another AES scheme',
      );
    });
  });

  group('cannot be opened', () {
    test('file exists, key missing: reported, no key created, file '
        'untouched', () async {
      final secrets = await createLedger();
      secrets.values.clear();
      final writesBefore = secrets.writes;
      final before = _snapshot(dir);

      final result = await open(secrets);
      expect(result, isA<LedgerCannotBeOpened>());
      expect(
        (result as LedgerCannotBeOpened).reason,
        LedgerUnreadableReason.keyMissing,
      );
      expect(secrets.values, isEmpty, reason: 'no new key');
      expect(secrets.writes, writesBefore);
      _expectUnchanged(dir, before);
    });

    test(
      'file exists, wrong key: reported, key kept, file untouched',
      () async {
        final secrets = await createLedger();
        final right = secrets.values[_keyName]!;
        // One hex digit different.
        final wrong = (right[0] == '0' ? '1' : '0') + right.substring(1);
        secrets.values[_keyName] = wrong;
        final before = _snapshot(dir);

        for (final background in [false, true]) {
          final result = await open(secrets, background: background);
          expect(result, isA<LedgerCannotBeOpened>());
          expect(
            (result as LedgerCannotBeOpened).reason,
            LedgerUnreadableReason.notReadableWithKey,
          );
        }
        expect(secrets.values[_keyName], wrong);
        _expectUnchanged(dir, before);

        // With the right key back, the data is all still there.
        secrets.values[_keyName] = right;
        final again = await open(secrets) as LedgerOpened;
        expect(await again.store.entriesForMonth(oct), [_entry('e1', 250)]);
        await again.store.close();
      },
    );

    test(
      'file exists, stored key malformed: reported, nothing changed',
      () async {
        final secrets = await createLedger();
        secrets.values[_keyName] = 'zz-not-hex';
        final before = _snapshot(dir);

        final result = await open(secrets);
        expect(result, isA<LedgerCannotBeOpened>());
        expect(
          (result as LedgerCannotBeOpened).reason,
          LedgerUnreadableReason.keyMalformed,
        );
        expect('$result', isNot(contains('zz-not-hex')));
        expect(secrets.values[_keyName], 'zz-not-hex');
        _expectUnchanged(dir, before);
      },
    );

    test('the file is not a database: reported, file untouched', () async {
      final secrets = await createLedger();
      final junk = Random(7);
      File(
        path,
      ).writeAsBytesSync(List.generate(8192, (_) => junk.nextInt(256)));
      final before = _snapshot(dir);

      final result = await open(secrets);
      expect(result, isA<LedgerCannotBeOpened>());
      expect(
        (result as LedgerCannotBeOpened).reason,
        LedgerUnreadableReason.notReadableWithKey,
      );
      _expectUnchanged(dir, before);
    });

    test('an unencrypted SQLite file at the path is not adopted', () async {
      Directory('${dir.path}/ledger').createSync();
      raw.sqlite3.open(path)
        ..execute('CREATE TABLE t (x TEXT)')
        ..execute("INSERT INTO t VALUES ('plain')")
        ..close();
      final secrets = FakeSecretStore({_keyName: List.filled(32, '11').join()});
      final before = _snapshot(dir);

      final result = await open(secrets);
      expect(result, isA<LedgerCannotBeOpened>());
      _expectUnchanged(dir, before);
    });

    test('a truncated database is reported and left as it is', () async {
      final secrets = await createLedger();
      final bytes = File(path).readAsBytesSync();
      File(path).writeAsBytesSync(bytes.sublist(0, 5000));
      final before = _snapshot(dir);

      final result = await open(secrets);
      expect(result, isNot(isA<LedgerOpened>()));
      _expectUnchanged(dir, before);
    });

    test('an empty file with no key is still "cannot be opened": no key is '
        'made for a file that already exists', () async {
      Directory('${dir.path}/ledger').createSync();
      File(path).writeAsBytesSync(const []);
      final secrets = FakeSecretStore();
      final before = _snapshot(dir);

      final result = await open(secrets);
      expect(result, isA<LedgerCannotBeOpened>());
      expect(secrets.values, isEmpty);
      _expectUnchanged(dir, before);
    });

    test(
      'repeated failed opens never create a journal or any other file',
      () async {
        final secrets = await createLedger();
        secrets.values.clear();
        final before = _snapshot(dir);
        for (var i = 0; i < 3; i++) {
          expect(
            await open(secrets, background: true),
            isA<LedgerCannotBeOpened>(),
          );
        }
        _expectUnchanged(dir, before);
      },
    );
  });

  group('other failure', () {
    test(
      'secure storage throws: reported as a failure, nothing created',
      () async {
        final secrets = FakeSecretStore()
          ..failWith = StateError('keystore down');
        final result = await open(secrets);
        expect(result, isA<LedgerOpenFailed>());
        expect((result as LedgerOpenFailed).error, isStateError);
        expect(Directory('${dir.path}/ledger').existsSync(), isFalse);
      },
    );

    test('secure storage throws while a database exists: failure, file '
        'untouched, and Retry works once storage recovers', () async {
      final secrets = await createLedger();
      final before = _snapshot(dir);
      secrets.failWith = StateError('keystore down');

      expect(await open(secrets), isA<LedgerOpenFailed>());
      _expectUnchanged(dir, before);

      secrets.failWith = null;
      final retry = await open(secrets);
      expect(retry, isA<LedgerOpened>());
      await (retry as LedgerOpened).store.close();
    });

    test('the path cannot be created: failure, and the new key is the only '
        'thing left behind', () async {
      // A plain file where the ledger directory should be.
      File('${dir.path}/ledger').writeAsStringSync('in the way');
      final secrets = FakeSecretStore();
      final result = await open(secrets);
      expect(result, isA<LedgerOpenFailed>());
      expect(File('${dir.path}/ledger').readAsStringSync(), 'in the way');
    });

    test('the key could not be saved: failure and no database file', () async {
      final secrets = _ForgetfulSecretStore();
      final result = await openLedger(
        path: path,
        secrets: secrets,
        background: false,
      );
      expect(result, isA<LedgerOpenFailed>());
      expect(File(path).existsSync(), isFalse);
    });
  });

  group('LedgerKeyVault', () {
    test(
      'creates 32 random bytes once and returns the same key after',
      () async {
        final secrets = FakeSecretStore();
        final vault = LedgerKeyVault(secrets);
        expect(await vault.read(), isNull);
        final key = await vault.readOrCreate();
        expect(key.length, 32);
        expect(await vault.readOrCreate(), key);
        expect(await LedgerKeyVault(secrets).read(), key);
        expect(secrets.writes, 1);
        expect(ledgerKeyHex(key), secrets.values[_keyName]);
      },
    );

    test('keys differ between installs', () async {
      final keys = <String>{};
      for (var i = 0; i < 50; i++) {
        final secrets = FakeSecretStore();
        await LedgerKeyVault(secrets).create();
        keys.add(secrets.values[_keyName]!);
      }
      expect(keys.length, 50);
    });

    test('a malformed stored value is refused without echoing it', () async {
      for (final bad in ['', 'abc', 'G' * 64, 'A' * 64, 'a' * 63, 'a' * 66]) {
        final vault = LedgerKeyVault(FakeSecretStore({_keyName: bad}));
        await expectLater(
          vault.read(),
          throwsA(
            isA<LedgerKeyMalformed>().having(
              (e) => '$e'.contains(bad) && bad.length > 3,
              'echoes the value',
              isFalse,
            ),
          ),
        );
      }
    });

    test('ledgerKeyHex insists on 32 bytes', () {
      expect(() => ledgerKeyHex(Uint8List(31)), throwsArgumentError);
      expect(ledgerKeyHex(Uint8List(32)), '0' * 64);
    });
  });

  test('backup exclusion does nothing off iOS', () async {
    expect(await excludeFromBackup('/tmp/anything'), isFalse);
  });
}

/// A secret store that accepts writes and keeps nothing.
class _ForgetfulSecretStore extends FakeSecretStore {
  @override
  Future<void> write(String name, String value) async {}
}
