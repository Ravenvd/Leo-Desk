import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/features/billing/models/bill.dart';
import 'package:leo_desk/features/billing/repositories/bill_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database database;
  late BillRepository windowsBills;
  late int customerId;
  final now = DateTime.utc(2026, 11, 1);

  setUp(() async {
    database = await AppDatabase.openTestDatabase();
    windowsBills = BillRepository(database: database, isNumberAuthority: true);
    customerId = await database.insert('customers', {
      'uuid': 'bill-number-customer',
      'sync_status': 'synced',
      'name': 'Bill number test customer',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    for (var i = 1; i <= 2; i++) {
      await database.insert('orders', {
        'uuid': 'bill-number-order-$i',
        'sync_status': 'synced',
        'order_number': 'ORD-00000$i',
        'customer_id': customerId,
        'order_date': now.toIso8601String(),
        'expected_delivery_date': now.add(const Duration(days: 7)).toIso8601String(),
        'stitching_required': 0,
        'stitching_price_paise': 0,
        'status': 'Completed',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
    }
  });

  tearDown(() async => database.close());

  test('Windows assigns distinct bill numbers despite identical client proposals', () async {
    for (var i = 1; i <= 2; i++) {
      final bill = Bill(
        uuid: 'offline-bill-$i',
        customerId: customerId,
        customerUuid: 'bill-number-customer',
        orderUuid: 'bill-number-order-$i',
        billNumber: 'BILL-COLLISION',
        billDate: now,
        subtotalPaise: 10000,
        totalPaise: 10000,
        createdAt: now,
        updatedAt: now,
      );
      expect(await windowsBills.upsertFromSync(bill, []), isTrue);
    }

    final saved = await windowsBills.getAll();
    expect(saved, hasLength(2));
    expect(saved.map((bill) => bill.billNumber).toSet(), {
      'BILL-20261101-000001',
      'BILL-20261101-000002',
    });
  });

  test('Windows retains the assigned bill number when a UUID is retried', () async {
    final incoming = Bill(
      uuid: 'offline-bill-retry',
      customerId: customerId,
      customerUuid: 'bill-number-customer',
      orderUuid: 'bill-number-order-1',
      billNumber: 'BILL-CLIENT-PROPOSAL',
      billDate: now,
      subtotalPaise: 10000,
      totalPaise: 10000,
      createdAt: now,
      updatedAt: now,
    );

    expect(await windowsBills.upsertFromSync(incoming, []), isTrue);
    final first = (await windowsBills.getAll()).single;
    expect(first.billNumber, 'BILL-20261101-000001');

    final retry = incoming.copyWith(
      billNumber: 'BILL-DIFFERENT-PROPOSAL',
      updatedAt: now.add(const Duration(minutes: 1)),
    );
    expect(await windowsBills.upsertFromSync(retry, []), isTrue);

    final saved = (await windowsBills.getAll()).single;
    expect(saved.uuid, incoming.uuid);
    expect(saved.billNumber, 'BILL-20261101-000001');
  });
  test('preserves pending bills and frees synced legacy number collisions', () async {
    final androidBills = BillRepository(database: database);
    final legacy = Bill(
      uuid: 'legacy-bill-number-owner',
      syncStatus: 'pending',
      customerId: customerId,
      customerUuid: 'bill-number-customer',
      orderUuid: 'bill-number-order-2',
      billNumber: 'BILL-20261101-000001',
      billDate: now,
      subtotalPaise: 10000,
      totalPaise: 10000,
      createdAt: now,
      updatedAt: now,
    );
    await database.insert('bills', legacy.toMap()..remove('id'));

    final incoming = Bill(
      uuid: 'windows-canonical-bill',
      customerId: customerId,
      customerUuid: 'bill-number-customer',
      orderUuid: 'bill-number-order-1',
      billNumber: 'BILL-20261101-000001',
      billDate: now,
      subtotalPaise: 12000,
      totalPaise: 12000,
      createdAt: now,
      updatedAt: now,
    );

    expect(await androidBills.upsertFromSync(incoming, []), isFalse);
    var savedLegacy = Bill.fromMap(
      (await database.query(
        'bills',
        where: 'uuid = ?',
        whereArgs: [legacy.uuid],
      )).single,
    );
    expect(savedLegacy.billNumber, incoming.billNumber);
    expect(savedLegacy.syncStatus, 'pending');

    await database.update(
      'bills',
      {'sync_status': 'synced'},
      where: 'uuid = ?',
      whereArgs: [legacy.uuid],
    );
    expect(await androidBills.upsertFromSync(incoming, []), isTrue);

    savedLegacy = Bill.fromMap(
      (await database.query(
        'bills',
        where: 'uuid = ?',
        whereArgs: [legacy.uuid],
      )).single,
    );
    final canonical = (await androidBills.getAll()).singleWhere(
      (bill) => bill.uuid == incoming.uuid,
    );
    expect(savedLegacy.uuid, legacy.uuid);
    expect(savedLegacy.billNumber, 'PENDING-${legacy.uuid}');
    expect(canonical.billNumber, incoming.billNumber);
  });

  test('does not replace a pending bill for the same order', () async {
    final androidBills = BillRepository(database: database);
    final pending = Bill(
      uuid: 'zzz-pending-bill',
      syncStatus: 'pending',
      customerId: customerId,
      customerUuid: 'bill-number-customer',
      orderUuid: 'bill-number-order-1',
      billNumber: 'BILL-LOCAL',
      billDate: now,
      subtotalPaise: 10000,
      totalPaise: 10000,
      createdAt: now,
      updatedAt: now,
    );
    await database.insert('bills', pending.toMap()..remove('id'));

    final incoming = Bill(
      uuid: 'aaa-windows-bill',
      customerId: customerId,
      customerUuid: 'bill-number-customer',
      orderUuid: 'bill-number-order-1',
      billNumber: 'BILL-WINDOWS',
      billDate: now,
      subtotalPaise: 12000,
      totalPaise: 12000,
      createdAt: now,
      updatedAt: now,
    );

    expect(await androidBills.upsertFromSync(incoming, []), isFalse);
    final saved = Bill.fromMap(
      (await database.query(
        'bills',
        where: 'uuid = ?',
        whereArgs: [pending.uuid],
      )).single,
    );
    expect(saved.uuid, pending.uuid);
    expect(saved.billNumber, pending.billNumber);
    expect(saved.syncStatus, 'pending');
    expect(await androidBills.getAll(), hasLength(1));
  });

}
