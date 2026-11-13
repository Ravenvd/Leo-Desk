import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/features/invoices/models/invoice.dart';
import 'package:leo_desk/features/invoices/models/invoice_item.dart';
import 'package:leo_desk/features/invoices/repositories/invoice_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDirectory;
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
    testDirectory = await Directory.systemTemp.createTemp('invoice_number_test_');
    windowsDb = await AppDatabase.openTestDatabase(
      path: '${testDirectory.path}${Platform.pathSeparator}windows.db',
    );
    androidDb = await AppDatabase.openTestDatabase(
      path: '${testDirectory.path}${Platform.pathSeparator}android.db',
    );
    (windowsCustomerId, windowsOrderId) = await seed(windowsDb);
    await seed(androidDb);
  });

  tearDown(() async {
    await windowsDb.close();
    await androidDb.close();
    await testDirectory.delete(recursive: true);
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

  test('Windows retains the canonical invoice number when a UUID is retried', () async {
    final windows = InvoiceRepository(
      database: windowsDb,
      isNumberAuthority: true,
    );
    final incoming = Invoice(
      uuid: 'offline-invoice-retry',
      orderId: windowsOrderId,
      orderUuid: orderUuid,
      customerId: windowsCustomerId,
      customerUuid: customerUuid,
      invoiceNumber: 'INV-CLIENT-PROPOSAL',
      invoiceDate: now,
      subtotalPaise: 10000,
      totalPaise: 10000,
      createdAt: now,
      updatedAt: now,
    );
    final items = [
      InvoiceItem(
        invoiceId: 0,
        description: 'Embroidery',
        quantity: 1,
        ratePaise: 10000,
        amountPaise: 10000,
      ),
    ];

    expect(await windows.upsertFromSync(incoming, items), isTrue);
    expect((await windows.getAll()).single.invoiceNumber, 'INV-000042');

    final retry = incoming.copyWith(
      invoiceNumber: 'INV-DIFFERENT-PROPOSAL',
      updatedAt: now.add(const Duration(minutes: 1)),
    );
    expect(await windows.upsertFromSync(retry, items), isTrue);

    final saved = (await windows.getAll()).single;
    expect(saved.uuid, incoming.uuid);
    expect(saved.invoiceNumber, 'INV-000042');
  });
  test('preserves pending invoice number owners and frees synced legacy collisions', () async {
    final androidSeed = await androidDb.query(
      'orders',
      columns: ['id'],
      where: 'uuid = ?',
      whereArgs: [orderUuid],
      limit: 1,
    );
    final androidCustomer = await androidDb.query(
      'customers',
      columns: ['id'],
      where: 'uuid = ?',
      whereArgs: [customerUuid],
      limit: 1,
    );
    final otherOrderId = await androidDb.insert('orders', {
      'uuid': 'invoice-number-other-order',
      'sync_status': 'synced',
      'order_number': 'ORD-000099',
      'customer_id': androidCustomer.single['id'],
      'order_date': now.toIso8601String(),
      'expected_delivery_date': now.add(const Duration(days: 7)).toIso8601String(),
      'stitching_required': 0,
      'stitching_price_paise': 0,
      'status': 'In Progress',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    final legacyInvoice = Invoice(
      uuid: 'legacy-invoice-number-owner',
      syncStatus: 'pending',
      orderId: otherOrderId,
      orderUuid: 'invoice-number-other-order',
      customerId: androidCustomer.single['id'] as int,
      customerUuid: customerUuid,
      invoiceNumber: 'INV-000042',
      invoiceDate: now,
      subtotalPaise: 10000,
      totalPaise: 10000,
      createdAt: now,
      updatedAt: now,
    );
    await androidDb.insert('invoices', legacyInvoice.toMap()..remove('id'));

    final incoming = Invoice(
      uuid: 'windows-canonical-invoice',
      orderId: androidSeed.single['id'] as int,
      orderUuid: orderUuid,
      customerId: androidCustomer.single['id'] as int,
      customerUuid: customerUuid,
      invoiceNumber: 'INV-000042',
      invoiceDate: now,
      subtotalPaise: 12000,
      totalPaise: 12000,
      createdAt: now,
      updatedAt: now,
    );
    final android = InvoiceRepository(database: androidDb);

    expect(await android.upsertFromSync(incoming, []), isFalse);
    var savedLegacy = Invoice.fromMap(
      (await androidDb.query(
        'invoices',
        where: 'uuid = ?',
        whereArgs: [legacyInvoice.uuid],
      )).single,
    );
    expect(savedLegacy.invoiceNumber, 'INV-000042');
    expect(savedLegacy.syncStatus, 'pending');

    await androidDb.update(
      'invoices',
      {'sync_status': 'synced'},
      where: 'uuid = ?',
      whereArgs: [legacyInvoice.uuid],
    );
    expect(await android.upsertFromSync(incoming, []), isTrue);

    savedLegacy = Invoice.fromMap(
      (await androidDb.query(
        'invoices',
        where: 'uuid = ?',
        whereArgs: [legacyInvoice.uuid],
      )).single,
    );
    final canonical = (await android.getAll()).singleWhere(
      (invoice) => invoice.uuid == incoming.uuid,
    );
    expect(savedLegacy.invoiceNumber, 'PENDING-${legacyInvoice.uuid}');
    expect(savedLegacy.uuid, legacyInvoice.uuid);
    expect(canonical.invoiceNumber, 'INV-000042');
  });

}
