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
}
