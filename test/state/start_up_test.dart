// Start-up against real encrypted files in a temporary directory, with a
// fake key store.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tide/budget/budget.dart';
import 'package:tide/state/start_up.dart';
import 'package:tide/storage/device_ledger.dart';

import '../support/failing_ledger_store.dart';
import '../support/fake_secret_store.dart';

class _UnreadableStore extends FailingLedgerStore {
  @override
  Future<List<Entry>> entriesForMonth(YearMonth month) async =>
      throw const LedgerStoreFailure('entriesForMonth');
}

void main() {
  late Directory dir;
  late String path;
  final oct5 = DateTime(2026, 10, 5, 10);
  const oct = YearMonth(2026, 10);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tide_start_test');
    path = '${dir.path}/ledger/tide.sqlite';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<StartResult> start(FakeSecretStore secrets) => startUp(
    open: () => openLedger(path: path, secrets: secrets, background: false),
    clock: () => oct5,
  );

  test('a first launch starts on an empty ledger with no budget', () async {
    final result = await start(FakeSecretStore());

    expect(result, isA<Started>());
    final started = result as Started;
    addTearDown(started.store.close);
    expect(started.start.month, oct);
    expect(started.start.hasBudget, isFalse);
    expect(started.start.budgetMinor, isNull);
    expect(started.start.incomeMinor, isNull);
    expect(started.start.entries, isEmpty);
    expect(started.start.categories, isEmpty);
    expect(started.start.frequentAmountsMinor, isEmpty);
  });

  test('a later launch starts with what was saved', () async {
    final secrets = FakeSecretStore();
    final first = await start(secrets) as Started;
    final entry = await first.store.insertEntry(
      Entry(
        id: newUuidV7(),
        type: EntryType.expense,
        amountMinor: rupees(250),
        categoryId: 'food',
        occurredAt: DateTime(2026, 10, 4, 13),
      ),
    );
    await first.store.setBudget(oct, rupees(32000));
    await first.store.saveProfile(Profile(monthlyIncomeMinor: rupees(45000)));
    await first.store.close();

    final second = await start(secrets) as Started;
    addTearDown(second.store.close);
    expect(second.start.hasBudget, isTrue);
    expect(second.start.budgetMinor, rupees(32000));
    expect(second.start.incomeMinor, rupees(45000));
    expect(second.start.entries, [entry]);
    expect(second.start.frequentAmountsMinor, [rupees(250)]);
  });

  test('saved data whose key is gone fails to start, is left untouched, '
      'and starts again once the key is back', () async {
    final secrets = FakeSecretStore();
    final first = await start(secrets) as Started;
    await first.store.setBudget(oct, rupees(30000));
    await first.store.close();
    final file = File(path);
    final bytes = file.readAsBytesSync();
    final modified = file.lastModifiedSync();
    final key = secrets.values.remove(LedgerKeyVault.defaultName)!;

    final failed = await start(secrets);
    expect(failed, isA<StartFailed>());
    expect(
      (failed as StartFailed).cause,
      isA<LedgerCannotBeOpened>().having(
        (c) => c.reason,
        'reason',
        LedgerUnreadableReason.keyMissing,
      ),
    );
    expect(file.readAsBytesSync(), bytes);
    expect(file.lastModifiedSync(), modified);
    expect(secrets.values, isEmpty, reason: 'no new key was made');

    // Retry is the same call.
    secrets.values[LedgerKeyVault.defaultName] = key;
    final retried = await start(secrets);
    expect(retried, isA<Started>());
    addTearDown((retried as Started).store.close);
    expect(retried.start.budgetMinor, rupees(30000));
  });

  test('a ledger that opens but cannot be read fails to start and is '
      'closed', () async {
    final store = _UnreadableStore();
    final result = await startUp(
      open: () async => LedgerOpened(store, created: false),
      clock: () => oct5,
    );

    expect(result, isA<StartFailed>());
    expect((result as StartFailed).cause, isA<LedgerOpenFailed>());
    expect((store.inner as MemoryLedgerStore).isClosed, isTrue);
  });

  test('an opener that throws is a failed start, not a crash', () async {
    final result = await startUp(open: () => throw StateError('no disk'));
    expect(result, isA<StartFailed>());
  });
}
