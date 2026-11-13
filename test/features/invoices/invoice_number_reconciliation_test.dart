import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/features/invoices/models/invoice.dart';
import 'package:leo_desk/features/invoices/models/invoice_item.dart';
import 'package:leo_desk/features/invoices/repositories/invoice_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database windowsDb;
  late Database androidDb;
  late int windowsCustomerId;
  late int windowsOrderId;
  const customerUuid = 'invoice-number-customer';
  const orderUuid = 'invoice-number-order';
  final now = DateTime.utc(2026, 11, 1);

  Future<(int, int)> seed(Database db) async {
    final customerId = await db.insert('customers', {
      'uuid': customerUuid,
      'sync_status': 'synced',
      'name': 'Invoice test customer',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    final orderId = await db.insert('orders', {
      'uuid': orderUuid,
      'sync_status': 'synced',
      'order_number': 'ORD-000042',
      'customer_id': customerId,
      'order_date': now.toIso8601String(),
      'expected_delivery_date': now.add(const Duration(days: 7)).toIso8601String(),
      'stitching_required': 0,
      'stitching_price_paise': 0,
      'status': 'In Progress',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    return (customerId, orderId);
  }

  setUp(() async {
    windowsDb = await AppDatabase.openTestDatabase();
    androidDb = await AppDatabase.openTestDatabase();
    (windowsCustomerId, windowsOrderId) = await seed(windowsDb);
    await seed(androidDb);
  });

  tearDown(() async {
    await windowsDb.close();
    await androidDb.close();
  });

  test('Windows derives invoice number from its canonical order number', () async {
    final windows = InvoiceRepository(
      database: windowsDb,
      isNumberAuthority: true,
    );
    final incoming = Invoice(
      uuid: 'offline-invoice-uuid',
      orderId: windowsOrderId,
      orderUuid: orderUuid,
      customerId: windowsCustomerId,
      customerUuid: customerUuid,
      invoiceNumber: 'INV-LOCAL-COLLISION',
      invoiceDate: now,
      subtotalPaise: 10000,
      totalPaise: 10000,
      createdAt: now,
      updatedAt: now,
    );

    expect(
      await windows.upsertFromSync(
        incoming,
        [
          InvoiceItem(
            invoiceId: 0,
            description: 'Embroidery',
            quantity: 1,
            ratePaise: 10000,
            amountPaise: 10000,
          ),
        ],
      ),
      isTrue,
    );

    final canonical = (await windows.getAll()).single;
    expect(canonical.invoiceNumber, 'INV-000042');

    final android = InvoiceRepository(
      database: androidDb,
      isNumberAuthority: false,
    );
    expect(
      await android.upsertFromSync(
        canonical,
        await windows.getItems(canonical.id!),
      ),
      isTrue,
    );
    expect((await android.getAll()).single.invoiceNumber, 'INV-000042');
  });
}
