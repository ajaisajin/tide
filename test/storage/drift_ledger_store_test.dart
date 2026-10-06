import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:tide/budget/budget.dart';
import 'package:tide/storage/device_ledger.dart';

import 'ledger_store_contract.dart';

void main() {
  ledgerStoreContract(
    'DriftLedgerStore (in memory)',
    () async => DriftLedgerStore.memory(),
  );

  group('encrypted file on the host', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('tide_drift_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    final key = Uint8List.fromList(List.generate(32, (i) => i * 7 + 1));
    var n = 0;

    // The contract again, this time through the cipher and a real file.
    ledgerStoreContract('DriftLedgerStore (encrypted file)', () async {
      final file = File('${dir.path}/contract-${n++}.sqlite');
      return DriftLedgerStore(
        TideDatabase(openEncryptedExecutor(file, key, background: false)),
      );
    });
  });

  group('DriftLedgerStore rows', () {
    late DriftLedgerStore store;
    var now = DateTime.utc(2026, 10, 5, 6, 30);

    setUp(() {
      now = DateTime.utc(2026, 10, 5, 6, 30);
      store = DriftLedgerStore.memory(clock: () => now);
    });
    tearDown(() => store.close());

    Future<Map<String, Object?>> row(
      String sql, [
      List<Object?> args = const [],
    ]) async =>
        (await store.database
                .customSelect(
                  sql,
                  variables: [for (final a in args) Variable(a)],
                )
                .getSingle())
            .data;

    test('schema version 1 with the four tables and two indexes', () async {
      expect(store.database.schemaVersion, 1);
      final names = await store.database
          .customSelect(
            "SELECT type, name, tbl_name FROM sqlite_master "
            "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
          )
          .get();
      expect(
        [
          for (final r in names)
            '${r.data['type']} ${r.data['name']} on ${r.data['tbl_name']}',
        ],
        [
          'index entries_category_id on entries',
          'index entries_occurred_at on entries',
          'table budgets on budgets',
          'table categories on categories',
          'table entries on entries',
          'table profile on profile',
        ],
      );
      Future<List<String>> columns(String table) async => [
        for (final r
            in await store.database
                .customSelect('PRAGMA table_info($table)')
                .get())
          r.data['name']! as String,
      ];
      expect(await columns('entries'), [
        'id', 'type', 'amount_minor', 'currency', 'category_id', 'note',
        'occurred_at', 'source', 'created_at', 'updated_at', 'deleted', //
      ]);
      expect(await columns('categories'), [
        'id', 'name', 'color', 'monthly_limit_minor', 'sort_order',
        'created_at', 'updated_at', 'deleted', //
      ]);
      expect(await columns('budgets'), [
        'month',
        'total_minor',
        'created_at',
        'updated_at',
      ]);
      expect(await columns('profile'), [
        'id',
        'monthly_income_minor',
        'home_currency',
      ]);
      expect((await row('PRAGMA user_version')).values.single, 1);
    });

    test('an entry is stored in UTC milliseconds with INR, timestamps and '
        'deleted = 0', () async {
      final at = DateTime(2026, 10, 5, 13, 45, 12, 345);
      await store.insertEntry(
        Entry(
          id: '019a2b3c-4d5e-7f01-8a2b-3c4d5e6f7a8b',
          type: EntryType.expense,
          amountMinor: rupees(250),
          categoryId: 'food',
          note: 'Lunch',
          occurredAt: at,
        ),
      );
      expect(await row('SELECT * FROM entries'), {
        'id': '019a2b3c-4d5e-7f01-8a2b-3c4d5e6f7a8b',
        'type': 'expense',
        'amount_minor': 25000,
        'currency': 'INR',
        'category_id': 'food',
        'note': 'Lunch',
        'occurred_at': at.toUtc().millisecondsSinceEpoch,
        'source': 'manual',
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
        'deleted': 0,
      });
    });

    test(
      'soft delete keeps the row, sets deleted and moves updated_at',
      () async {
        final created = now;
        await store.insertEntry(
          Entry(
            id: 'e1',
            type: EntryType.expense,
            amountMinor: rupees(250),
            occurredAt: DateTime(2026, 10, 5),
          ),
        );
        now = now.add(const Duration(minutes: 3));
        expect(await store.softDeleteEntry('e1'), isTrue);
        final r = await row(
          'SELECT deleted, created_at, updated_at FROM entries',
        );
        expect(r, {
          'deleted': 1,
          'created_at': created.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
        });
      },
    );

    test('budgets are keyed YYYY-MM; setting again keeps created_at', () async {
      final created = now;
      await store.setBudget(const YearMonth(2026, 3), rupees(30000));
      now = now.add(const Duration(days: 2));
      await store.setBudget(const YearMonth(2026, 3), rupees(32000));
      expect(await row('SELECT * FROM budgets'), {
        'month': '2026-03',
        'total_minor': 3200000,
        'created_at': created.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
      });
    });

    test('categories keep sort order; a dropped one is flagged, not '
        'removed', () async {
      final a = Category(
        id: 'a',
        name: 'A',
        colorValue: 0xFFF2B880,
        limitMinor: 100,
      );
      final b = Category(
        id: 'b',
        name: 'B',
        colorValue: 0xFF000000,
        limitMinor: 200,
      );
      await store.replaceCategories([a, b]);
      await store.replaceCategories([b]);
      final rows = await store.database
          .customSelect(
            'SELECT id, color, sort_order, deleted FROM categories ORDER BY id',
          )
          .get();
      expect(
        [for (final r in rows) r.data],
        [
          {'id': 'a', 'color': 0xFFF2B880, 'sort_order': 0, 'deleted': 1},
          {'id': 'b', 'color': 0xFF000000, 'sort_order': 0, 'deleted': 0},
        ],
      );
    });

    test('the profile table holds one row', () async {
      await store.saveProfile(const Profile(monthlyIncomeMinor: 4500000));
      await store.saveProfile(const Profile(monthlyIncomeMinor: 5000000));
      expect(await row('SELECT * FROM profile'), {
        'id': 1,
        'monthly_income_minor': 5000000,
        'home_currency': 'INR',
      });
      await expectLater(
        store.database.customStatement(
          "INSERT INTO profile (id, monthly_income_minor) VALUES (2, 1)",
        ),
        throwsA(anything),
      );
    });

    test('the month query uses the occurred_at index', () async {
      final plan = await store.database
          .customSelect(
            'EXPLAIN QUERY PLAN SELECT * FROM entries '
            'WHERE deleted = 0 AND occurred_at >= 1 AND occurred_at < 2',
          )
          .get();
      expect(
        plan.map((r) => r.data['detail']).join(' '),
        contains('entries_occurred_at'),
      );
    });
  });
}
