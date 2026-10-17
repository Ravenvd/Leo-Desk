import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/features/billing/models/bill.dart';
import 'package:leo_desk/features/billing/models/bill_item.dart';
import 'package:leo_desk/features/billing/repositories/bill_repository.dart';
import 'package:leo_desk/features/customers/models/customer.dart';
import 'package:leo_desk/features/customers/repositories/customer_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database database;
  late BillRepository bills;
  late Customer customer;
  const orderUuid = 'bill-conflict-order';
  final early = DateTime.utc(2026, 10, 1, 9);
  final late = DateTime.utc(2026, 10, 1, 10);

  setUp(() async {
    database = await AppDatabase.openTestDatabase();
    bills = BillRepository(database: database);
    final now = DateTime.utc(2026, 10, 1);
    final customerId = await CustomerRepository(database: database).insert(
      Customer(
        uuid: 'bill-conflict-customer',
        name: 'Conflict Test Customer',
        createdAt: now,
        updatedAt: now,
      ),
    );
    customer = (await CustomerRepository(database: database).getById(customerId))!;

    await database.insert('orders', {
      'uuid': orderUuid,
      'sync_status': 'synced',
      'order_number': 'ORD-000001',
      'customer_id': customerId,
      'order_date': now.toIso8601String(),
      'expected_delivery_date': now.add(const Duration(days: 7)).toIso8601String(),
      'stitching_required': 1,
      'stitching_price_paise': 10000,
      'status': 'New',
      'notes': null,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
  });

  tearDown(() async {
    await database.close();
  });

  Bill makeBill({
    required String uuid,
    required String number,
    required DateTime createdAt,
  }) {
    return Bill(
      uuid: uuid,
      customerId: customer.id!,
      customerUuid: customer.uuid,
      orderUuid: orderUuid,
      billNumber: number,
      billDate: createdAt,
      subtotalPaise: 10000,
      totalPaise: 10000,
      notes: 'Bill $uuid',
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  BillItem makeItem(String uuid, String description) {
    return BillItem(
      uuid: uuid,
      billId: 0,
      description: description,
      quantity: 1,
      ratePaise: 10000,
      amountPaise: 10000,
    );
  }

  Future<void> insertLocalBill(Bill bill, String itemUuid) async {
    await bills.insert(
      bill: bill,
      items: [makeItem(itemUuid, 'Local ${bill.billNumber}')],
    );
  }

  test('earliest incoming bill replaces a later pending local bill and items',
      () async {
    await insertLocalBill(
      makeBill(uuid: 'later-local', number: 'BILL-LATE', createdAt: late),
      'later-local-item',
    );

    final applied = await bills.upsertFromSync(
      makeBill(uuid: 'earlier-server', number: 'BILL-EARLY', createdAt: early),
      [makeItem('earlier-server-item', 'Winning item')],
    );

    expect(applied, isTrue);
    final allBills = await bills.getAll();
    expect(allBills, hasLength(1));
    expect(allBills.single.uuid, 'earlier-server');
    expect(allBills.single.billNumber, 'BILL-EARLY');
    expect(allBills.single.syncStatus, 'synced');

    final items = await bills.getItems(allBills.single.id!);
    expect(items, hasLength(1));
    expect(items.single.uuid, 'earlier-server-item');
    expect(items.single.description, 'Winning item');
  });

  test('later incoming bill cannot replace the earliest local bill', () async {
    await insertLocalBill(
      makeBill(uuid: 'earlier-local', number: 'BILL-EARLY', createdAt: early),
      'earlier-local-item',
    );

    final applied = await bills.upsertFromSync(
      makeBill(uuid: 'later-server', number: 'BILL-LATE', createdAt: late),
      [makeItem('later-server-item', 'Losing item')],
    );

    expect(applied, isFalse);
    final allBills = await bills.getAll();
    expect(allBills, hasLength(1));
    expect(allBills.single.uuid, 'earlier-local');
    expect(allBills.single.billNumber, 'BILL-EARLY');

    final items = await bills.getItems(allBills.single.id!);
    expect(items, hasLength(1));
    expect(items.single.uuid, 'earlier-local-item');
  });

  test('equal timestamps use UUID order as a deterministic tie-breaker',
      () async {
    await insertLocalBill(
      makeBill(uuid: 'z-local', number: 'BILL-Z', createdAt: early),
      'z-local-item',
    );

    final applied = await bills.upsertFromSync(
      makeBill(uuid: 'a-server', number: 'BILL-A', createdAt: early),
      [makeItem('a-server-item', 'Tie-break winner')],
    );

    expect(applied, isTrue);
    final allBills = await bills.getAll();
    expect(allBills, hasLength(1));
    expect(allBills.single.uuid, 'a-server');
    expect(allBills.single.billNumber, 'BILL-A');
  });

  test('does not delete a bill from another order to resolve bill-number clash',
      () async {
    await insertLocalBill(
      makeBill(uuid: 'existing-bill', number: 'BILL-SHARED', createdAt: early),
      'existing-item',
    );

    // The incoming bill belongs to another order but tries to reuse the
    // globally unique bill number. It must be rejected without deleting data.
    await database.insert('orders', {
      'uuid': 'another-order',
      'sync_status': 'synced',
      'order_number': 'ORD-000002',
      'customer_id': customer.id,
      'order_date': early.toIso8601String(),
      'expected_delivery_date': late.toIso8601String(),
      'stitching_required': 1,
      'stitching_price_paise': 10000,
      'status': 'New',
      'notes': null,
      'created_at': early.toIso8601String(),
      'updated_at': early.toIso8601String(),
    });

    final applied = await bills.upsertFromSync(
      makeBill(uuid: 'other-order-bill', number: 'BILL-SHARED', createdAt: early)
          .copyWith(orderUuid: 'another-order'),
      [makeItem('other-order-item', 'Should not apply')],
    );

    expect(applied, isFalse);
    final allBills = await bills.getAll();
    expect(allBills, hasLength(1));
    expect(allBills.single.uuid, 'existing-bill');
    expect((await bills.getItems(allBills.single.id!)).single.uuid,
        'existing-item');
  });
}
