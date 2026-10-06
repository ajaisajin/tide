// On-device check of the encrypted ledger: real secure storage, the real
// SQLite build, the real entry point.
//
//   flutter test integration_test/encrypted_ledger_test.dart -d emulator-5554
//
// It uses the app's real ledger path and key name, so it refuses to start on
// an install that already holds a ledger, and removes what it made when it
// finishes. (`flutter test` installs its own build of the app and uninstalls
// it afterwards.)
//
// Add --dart-define=TIDE_IT_HOLD_SECONDS=90 to make it wait, with the ledger
// closed and still on the device, so the file can be pulled and inspected
// from the development machine:
//
//   adb exec-out run-as app.tide.tide cat files/ledger/tide.sqlite > pulled.sqlite
//
// Lines it prints start with "TIDE_IT". The key is never printed.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:tide/budget/budget.dart';
import 'package:tide/storage/device_ledger.dart';

import '../test/storage/ledger_store_contract.dart';

const _holdSeconds = int.fromEnvironment('TIDE_IT_HOLD_SECONDS');
const _keyName = LedgerKeyVault.defaultName;
const _secrets = PlatformSecretStore();

void _say(String message) {
  // ignore: avoid_print
  print('TIDE_IT $message');
}

bool _containsBytes(Uint8List haystack, List<int> needle) {
  if (needle.isEmpty || haystack.length < needle.length) return false;
  final first = needle[0];
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    if (haystack[i] != first) continue;
    for (var j = 1; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const oct = YearMonth(2026, 10);
  final entries = [
    Entry(
      id: newUuidV7(),
      type: EntryType.expense,
      amountMinor: rupees(250),
      categoryId: 'food',
      note: 'Paneer tikka lunch',
      occurredAt: DateTime(2026, 10, 5, 13, 5),
    ),
    Entry(
      id: newUuidV7(),
      type: EntryType.expense,
      amountMinor: rupees(1850),
      categoryId: 'shop',
      note: 'Running shoes zebra',
      occurredAt: DateTime(2026, 10, 6, 18, 30),
    ),
    Entry(
      id: newUuidV7(),
      type: EntryType.income,
      amountMinor: rupees(5000),
      note: 'Freelance walrus',
      occurredAt: DateTime(2026, 10, 7, 9),
    ),
  ];
  final categories = [
    Category(
      id: 'food',
      name: 'Foodstuffs',
      colorValue: 0xFFF2B880,
      limitMinor: rupees(6000),
    ),
    Category(
      id: 'shop',
      name: 'Shopping',
      colorValue: 0xFFF29BB8,
      limitMinor: rupees(2100),
    ),
  ];
  final profile = Profile(monthlyIncomeMinor: rupees(45000));

  testWidgets('the ledger opens encrypted, survives a reopen with the same '
      'key, and is reported, not replaced, when its key is gone', (
    tester,
  ) async {
    final path = await defaultLedgerPath();
    final file = File(path);
    _say('path=$path');
    expect(
      file.existsSync(),
      isFalse,
      reason:
          'This install already has a ledger. This test only runs on a '
          'clean install, so that it can never touch real data.',
    );
    addTearDown(() async {
      if (file.parent.existsSync()) file.parent.deleteSync(recursive: true);
      await _secrets.delete(_keyName);
      _say('cleaned up: ledger directory and key removed');
    });

    // --- First open: creates the key and the file. ---
    final first = await openLedger();
    expect(first, isA<LedgerOpened>(), reason: '$first');
    first as LedgerOpened;
    expect(first.created, isTrue);
    final keyHex = (await _secrets.read(_keyName))!;
    expect(keyHex, matches(RegExp(r'^[0-9a-f]{64}$')));
    _say('first open: opened, created=true, key stored (64 hex digits)');

    for (final e in entries) {
      expect(await first.store.insertEntry(e), e);
    }
    await first.store.replaceCategories(categories);
    await first.store.setBudget(oct, rupees(30000));
    await first.store.saveProfile(profile);
    await first.store.close();

    // --- Second open: same key, same data. ---
    final second = await openLedger();
    expect(second, isA<LedgerOpened>(), reason: '$second');
    second as LedgerOpened;
    expect(second.created, isFalse);
    expect(await _secrets.read(_keyName), keyHex, reason: 'key reused');
    expect(await second.store.entriesForMonth(oct), entries);
    expect(await second.store.loadCategories(), categories);
    expect(await second.store.budgetFor(oct), rupees(30000));
    expect(await second.store.budgetFor(oct.next), rupees(30000));
    expect(await second.store.loadProfile(), profile);
    expect(await second.store.frequentExpenseAmounts(), [
      rupees(1850),
      rupees(250),
    ]);
    expect(await second.store.softDeleteEntry(entries[1].id), isTrue);
    await second.store.close();
    _say(
      'second open: created=false, key unchanged, 3 entries, categories, '
      'budget and profile read back equal',
    );

    // --- The cipher in effect, read on the device. ---
    final key = (await LedgerKeyVault(_secrets).read())!;
    {
      final db = raw.sqlite3.open(path, mode: raw.OpenMode.readOnly);
      applyLedgerCipher(db, ledgerKeyHex(key));
      final rows = db.select('SELECT count(*) AS n FROM entries').single['n'];
      final pragmas = {
        for (final name in [
          'cipher',
          'legacy',
          'legacy_page_size',
          'hmac_use',
          'hmac_algorithm',
          'kdf_algorithm',
          'kdf_iter',
        ])
          name: db.select('PRAGMA $name').single.values.single,
      };
      final version = db.select('SELECT sqlite_version() AS v').single['v'];
      db.close();
      _say('pragmas=$pragmas sqlite=$version entry_rows=$rows');
      expect(pragmas['cipher'], 'sqlcipher');
      expect('${pragmas['legacy']}', '4');
      expect(rows, 3);

      // On a connection where nothing is chosen, the default is not AES.
      final plain = raw.sqlite3.openInMemory();
      _say(
        'library default cipher=${plain.select('PRAGMA cipher').single.values.single}',
      );
      plain.close();

      // Without the key, with the wrong scheme, or without legacy = 4.
      for (final (label, setup) in [
        ('no key', <String>[]),
        (
          'key under default cipher',
          ['PRAGMA key = "x\'${ledgerKeyHex(key)}\'"'],
        ),
        (
          'sqlcipher without legacy=4',
          [
            "PRAGMA cipher = 'sqlcipher'",
            'PRAGMA key = "x\'${ledgerKeyHex(key)}\'"',
          ],
        ),
      ]) {
        final attempt = raw.sqlite3.open(path, mode: raw.OpenMode.readOnly);
        for (final statement in setup) {
          attempt.execute(statement);
        }
        Object? outcome;
        try {
          attempt.select('SELECT count(*) FROM sqlite_master');
          outcome = 'READ';
        } on raw.SqliteException catch (e) {
          outcome = 'SqliteException(${e.resultCode})';
        }
        attempt.close();
        _say('open with $label -> $outcome');
        expect(outcome, 'SqliteException(26)');
      }
    }

    // --- The file holds no plain text. ---
    final bytes = file.readAsBytesSync();
    _say(
      'file size=${bytes.length} first16=${_hex(bytes.sublist(0, 16))} '
      'bytes16to23=${_hex(bytes.sublist(16, 24))}',
    );
    expect(_containsBytes(bytes, ascii.encode('SQLite format 3')), isFalse);
    for (final plain in [
      'Paneer', 'tikka', 'zebra', 'walrus', 'Foodstuffs', 'Shopping', //
      'entries', 'categories', 'budgets', 'expense', 'manual', 'INR', '2026-10',
    ]) {
      expect(_containsBytes(bytes, utf8.encode(plain)), isFalse, reason: plain);
    }

    // --- The key is in no file under the app's data directory. ---
    final dataDir = (await getApplicationSupportDirectory()).parent;
    final forms = <String, List<int>>{
      'hex': ascii.encode(keyHex),
      'HEX': ascii.encode(keyHex.toUpperCase()),
      'raw bytes': key,
      'base64 of bytes': ascii.encode(base64.encode(key)),
      'base64url of bytes': ascii.encode(base64Url.encode(key)),
      'base64 of hex': ascii.encode(base64.encode(ascii.encode(keyHex))),
      // In case a file held only part of it.
      'first half of hex': ascii.encode(keyHex.substring(0, 32)),
      'second half of hex': ascii.encode(keyHex.substring(32)),
      'first 16 raw bytes': key.sublist(0, 16),
    };
    var scanned = 0;
    var unreadable = 0;
    final hits = <String>[];
    for (final item in dataDir.listSync(recursive: true, followLinks: false)) {
      if (item is! File) continue;
      Uint8List content;
      try {
        content = item.readAsBytesSync();
      } on FileSystemException {
        unreadable++;
        continue;
      }
      scanned++;
      final relative = item.path.substring(dataDir.path.length + 1);
      if (!relative.startsWith('code_cache') && !relative.startsWith('cache')) {
        _say('scanned $relative (${content.length} bytes)');
      }
      for (final MapEntry(key: form, value: needle) in forms.entries) {
        if (_containsBytes(content, needle)) hits.add('$relative: $form');
      }
    }
    _say(
      'key scan: dir=${dataDir.path} files=$scanned unreadable=$unreadable '
      'forms=${forms.length} hits=${hits.length}',
    );
    expect(scanned, greaterThan(1));
    expect(hits, isEmpty, reason: 'the key must not be in any ordinary file');

    // --- Time for the development machine to pull the file. ---
    if (_holdSeconds > 0) {
      _say('HOLD ${_holdSeconds}s: pull $path now');
      await Future<void>.delayed(const Duration(seconds: _holdSeconds));
      _say('HOLD over');
    }

    // --- Key gone while the file exists: cannot be opened, file untouched. ---
    List<Object?> fingerprint() => [
      file.lengthSync(),
      file.lastModifiedSync(),
      _hex(file.readAsBytesSync()),
      [for (final f in file.parent.listSync()) f.path]..sort(),
    ];
    final before = fingerprint();
    _say(
      'before key removal: size=${before[0]} mtime=${before[1]} '
      'files=${before[3]}',
    );

    await _secrets.delete(_keyName);
    expect(await _secrets.read(_keyName), isNull);
    // mtime has one-second resolution on some file systems.
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    final keyless = await openLedger();
    _say('open with key removed -> $keyless');
    expect(keyless, isA<LedgerCannotBeOpened>());
    expect(
      (keyless as LedgerCannotBeOpened).reason,
      LedgerUnreadableReason.keyMissing,
    );
    expect(await _secrets.read(_keyName), isNull, reason: 'no new key made');
    expect(fingerprint(), before);

    // --- A different key: also cannot be opened, file untouched. ---
    final wrongHex = keyHex.split('').reversed.join();
    expect(wrongHex, isNot(keyHex));
    await _secrets.write(_keyName, wrongHex);
    final wrong = await openLedger();
    _say('open with a different key -> $wrong');
    expect(wrong, isA<LedgerCannotBeOpened>());
    expect(
      (wrong as LedgerCannotBeOpened).reason,
      LedgerUnreadableReason.notReadableWithKey,
    );
    expect(await _secrets.read(_keyName), wrongHex);
    expect(fingerprint(), before);
    final after = fingerprint();
    _say(
      'after both failed opens: size=${after[0]} mtime=${after[1]} '
      'files=${after[3]} bytes_equal=${after[2] == before[2]}',
    );

    // --- The right key back: everything is still there. ---
    await _secrets.write(_keyName, keyHex);
    final restored = await openLedger();
    expect(restored, isA<LedgerOpened>(), reason: '$restored');
    restored as LedgerOpened;
    expect(await restored.store.entriesForMonth(oct), [entries[0], entries[2]]);
    expect(await restored.store.budgetFor(oct), rupees(30000));
    await restored.store.close();
    _say('open with the original key restored -> opened, data intact');
  });

  // The shared contract, through the cipher, on the device's own SQLite.
  group('on device', () {
    late Directory dir;
    final key = Uint8List.fromList(List.generate(32, (i) => 255 - i * 3));
    var n = 0;

    setUpAll(() async {
      dir = (await getTemporaryDirectory()).createTempSync('tide_contract');
    });
    tearDownAll(() => dir.deleteSync(recursive: true));

    ledgerStoreContract(
      'DriftLedgerStore (encrypted, background isolate)',
      () async {
        final file = File('${dir.path}/contract-${n++}.sqlite');
        return DriftLedgerStore(TideDatabase(openEncryptedExecutor(file, key)));
      },
    );
  });
}
