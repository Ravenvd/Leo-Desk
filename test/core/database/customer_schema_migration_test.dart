import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:leo_desk/core/database/database_schema.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String databasePath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'leo_customer_migration_test',
    );
    databasePath = '${tempDir.path}/v11.db';
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('migrates customers from v11 to v12 without losing data', () async {
    final v11Database = await openDatabase(
      databasePath,
      version: 11,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE customers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid TEXT NOT NULL UNIQUE,
            sync_status TEXT NOT NULL DEFAULT 'synced',
            name TEXT NOT NULL,
            phone TEXT,
            whatsapp TEXT,
            email TEXT,
            address TEXT,
            notes TEXT,
            customer_type TEXT NOT NULL,
            service_required TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE orders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid TEXT NOT NULL UNIQUE,
            sync_status TEXT NOT NULL DEFAULT 'synced',
            order_number TEXT NOT NULL UNIQUE,
            customer_id INTEGER NOT NULL,
            order_date TEXT NOT NULL,
            expected_delivery_date TEXT NOT NULL,
            stitching_required INTEGER NOT NULL DEFAULT 0,
            stitching_price_paise INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'New',
            notes TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (customer_id)
              REFERENCES customers(id)
              ON DELETE RESTRICT
          )
        ''');

        await db.execute('''
          CREATE TABLE invoices (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid TEXT NOT NULL UNIQUE,
            sync_status TEXT NOT NULL DEFAULT 'synced',
            order_id INTEGER NOT NULL UNIQUE,
            order_uuid TEXT NOT NULL UNIQUE,
            customer_id INTEGER NOT NULL,
            customer_uuid TEXT,
            invoice_number TEXT NOT NULL UNIQUE,
            invoice_date TEXT NOT NULL,
            subtotal_paise INTEGER NOT NULL DEFAULT 0,
            total_paise INTEGER NOT NULL DEFAULT 0,
            notes TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (order_id)
              REFERENCES orders(id)
              ON DELETE RESTRICT,
            FOREIGN KEY (customer_id)
              REFERENCES customers(id)
              ON DELETE RESTRICT
          )
        ''');

        await db.execute('''
          CREATE TABLE bills (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid TEXT NOT NULL UNIQUE,
            sync_status TEXT NOT NULL DEFAULT 'synced',
            customer_id INTEGER NOT NULL,
            customer_uuid TEXT,
            order_id INTEGER,
            order_uuid TEXT,
            bill_number TEXT NOT NULL UNIQUE,
            bill_date TEXT NOT NULL,
            subtotal_paise INTEGER NOT NULL DEFAULT 0,
            discount_paise INTEGER NOT NULL DEFAULT 0,
            tax_paise INTEGER NOT NULL DEFAULT 0,
            total_paise INTEGER NOT NULL DEFAULT 0,
            amount_paid_paise INTEGER NOT NULL DEFAULT 0,
            notes TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (customer_id)
              REFERENCES customers(id)
              ON DELETE RESTRICT
          )
        ''');
      },
    );

    const customerUuid = 'customer-v11-uuid';
    const orderUuid = 'order-v11-uuid';
    const invoiceUuid = 'invoice-v11-uuid';
    const billUuid = 'bill-v11-uuid';

    final customerId = await v11Database.insert('customers', {
      'uuid': customerUuid,
      'sync_status': 'synced',
      'name': 'Migration Test Customer',
      'phone': '9876543210',
      'whatsapp': '9876543210',
      'email': 'migration@example.com',
      'address': 'Test Address',
      'notes': 'Customer data must survive migration',
      'customer_type': 'Personal',
      'service_required': 'Embroidery',
      'created_at': '2026-09-24T10:00:00.000',
      'updated_at': '2026-09-24T10:00:00.000',
    });

    final orderId = await v11Database.insert('orders', {
      'uuid': orderUuid,
      'sync_status': 'synced',
      'order_number': 'ORD-MIGRATION-001',
      'customer_id': customerId,
      'order_date': '2026-09-24T10:00:00.000',
      'expected_delivery_date': '2026-09-30T10:00:00.000',
      'stitching_required': 1,
      'stitching_price_paise': 15000,
      'status': 'New',
      'notes': 'Migration test order',
      'created_at': '2026-09-24T10:00:00.000',
      'updated_at': '2026-09-24T10:00:00.000',
    });

    await v11Database.insert('invoices', {
      'uuid': invoiceUuid,
      'sync_status': 'synced',
      'order_id': orderId,
      'order_uuid': orderUuid,
      'customer_id': customerId,
      'customer_uuid': customerUuid,
      'invoice_number': 'INV-MIGRATION-001',
      'invoice_date': '2026-09-24T10:00:00.000',
      'subtotal_paise': 15000,
      'total_paise': 15000,
      'notes': 'Migration test invoice',
      'created_at': '2026-09-24T10:00:00.000',
      'updated_at': '2026-09-24T10:00:00.000',
    });

    await v11Database.insert('bills', {
      'uuid': billUuid,
      'sync_status': 'synced',
      'customer_id': customerId,
      'customer_uuid': customerUuid,
      'order_id': orderId,
      'order_uuid': orderUuid,
      'bill_number': 'BILL-MIGRATION-001',
      'bill_date': '2026-09-24T10:00:00.000',
      'subtotal_paise': 15000,
      'total_paise': 15000,
      'amount_paid_paise': 10000,
      'notes': 'Migration test bill',
      'created_at': '2026-09-24T10:00:00.000',
      'updated_at': '2026-09-24T10:00:00.000',
    });

    await v11Database.close();

    final v12Database = await openDatabase(
      databasePath,
      version: 12,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 12) {
          await DatabaseSchema.upgradeToVersion12(db);
        }
      },
    );

    final customers = await v12Database.query(
      'customers',
      where: 'uuid = ?',
      whereArgs: [customerUuid],
    );

    expect(customers, hasLength(1));

    final customer = customers.single;

    expect(customer['id'], customerId);
    expect(customer['uuid'], customerUuid);
    expect(customer['name'], 'Migration Test Customer');
    expect(customer['phone'], '9876543210');
    expect(customer['whatsapp'], '9876543210');
    expect(customer['email'], 'migration@example.com');
    expect(customer['address'], 'Test Address');
    expect(customer['notes'], 'Customer data must survive migration');
    expect(customer['sync_status'], 'synced');

    final customerColumns = await v12Database.rawQuery(
      'PRAGMA table_info(customers)',
    );

    final columnNames = customerColumns
        .map((column) => column['name'])
        .toList();

    expect(columnNames, isNot(contains('customer_type')));
    expect(columnNames, isNot(contains('service_required')));

    final orders = await v12Database.query(
      'orders',
      where: 'uuid = ?',
      whereArgs: [orderUuid],
    );

    expect(orders, hasLength(1));
    expect(orders.single['customer_id'], customerId);
    expect(orders.single['uuid'], orderUuid);

    final invoices = await v12Database.query(
      'invoices',
      where: 'uuid = ?',
      whereArgs: [invoiceUuid],
    );

    expect(invoices, hasLength(1));
    expect(invoices.single['customer_id'], customerId);
    expect(invoices.single['customer_uuid'], customerUuid);
    expect(invoices.single['order_id'], orderId);
    expect(invoices.single['order_uuid'], orderUuid);

    final bills = await v12Database.query(
      'bills',
      where: 'uuid = ?',
      whereArgs: [billUuid],
    );

    expect(bills, hasLength(1));
    expect(bills.single['customer_id'], customerId);
    expect(bills.single['customer_uuid'], customerUuid);
    expect(bills.single['order_id'], orderId);
    expect(bills.single['order_uuid'], orderUuid);

    expect(await v12Database.getVersion(), 12);

    await v12Database.close();
  });

  test('v12 customer migration is safe when legacy columns are already absent', () async {
    final database = await openDatabase(
      databasePath,
      version: DatabaseSchema.version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        for (final statement in DatabaseSchema.createStatements) {
          await db.execute(statement);
        }
      },
    );

    await expectLater(
      DatabaseSchema.upgradeToVersion12(database),
      completes,
    );

    final customerColumns = await database.rawQuery(
      'PRAGMA table_info(customers)',
    );
    final columnNames = customerColumns
        .map((column) => column['name'])
        .toList();

    expect(columnNames, isNot(contains('customer_type')));
    expect(columnNames, isNot(contains('service_required')));

    await database.close();
  });
}
