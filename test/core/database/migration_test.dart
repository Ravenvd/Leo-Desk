import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:leo_desk/core/database/database_schema.dart';

/// Schema as it existed at version 4 (before bill sync columns).
const _v4Statements = [
  '''
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
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    customer_type TEXT NOT NULL,
    service_required TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE bills (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id INTEGER NOT NULL,
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
    FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE RESTRICT
  )
  ''',
  '''
  CREATE TABLE bill_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    bill_id INTEGER NOT NULL,
    description TEXT NOT NULL,
    quantity REAL NOT NULL,
    rate_paise INTEGER NOT NULL,
    amount_paise INTEGER NOT NULL,
    FOREIGN KEY (bill_id) REFERENCES bills(id) ON DELETE CASCADE
  )
  ''',
];

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database database;

  setUp(() async {
    database = await openDatabase(
      inMemoryDatabasePath,
      version: 4,
      onCreate: (db, version) async {
        for (final statement in _v4Statements) {
          await db.execute(statement);
        }
      },
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('v5 migration backfills uuids and customer links', () async {
    final now = DateTime.now().toIso8601String();

    final customerId = await database.insert('customers', {
      'uuid': 'customer-uuid-1',
      'sync_status': 'synced',
      'name': 'Alice',
      'created_at': now,
      'updated_at': now,
      'customer_type': 'personal',
      'service_required': 'embroidery',
    });

    final billId = await database.insert('bills', {
      'customer_id': customerId,
      'bill_number': 'INV-0001',
      'bill_date': now,
      'subtotal_paise': 1000,
      'total_paise': 1000,
      'amount_paid_paise': 1000,
      'created_at': now,
      'updated_at': now,
    });

    final itemId = await database.insert('bill_items', {
      'bill_id': billId,
      'description': 'Logo embroidery',
      'quantity': 1.0,
      'rate_paise': 1000,
      'amount_paise': 1000,
    });

    await DatabaseSchema.upgradeToVersion5(database);

    final bills = await database.query('bills');
    expect(bills.length, 1);
    expect(bills.first['uuid'], isNotNull);
    expect((bills.first['uuid'] as String).isNotEmpty, isTrue);
    expect(bills.first['sync_status'], 'synced');
    expect(bills.first['customer_uuid'], 'customer-uuid-1');

    final items = await database.query('bill_items');
    expect(items.length, 1);
    expect(items.first['uuid'], isNotNull);
    expect((items.first['uuid'] as String).isNotEmpty, isTrue);

    // The unique index must reject duplicate bill uuids.
    final duplicate = Map<String, Object?>.from(bills.first)
      ..remove('id')
      ..['bill_number'] = 'INV-0002';
    expect(
      () => database.insert('bills', duplicate),
      throwsA(isA<DatabaseException>()),
    );

    // Item row is untouched apart from the new uuid.
    expect(items.first['id'], itemId);
    expect(items.first['description'], 'Logo embroidery');
  });

  test('v6 migration repairs customers table missing sync_status',
      () async {
    final now = DateTime.now().toIso8601String();

    // Simulate a database created by an intermediate build: customers
    // has uuid but no sync_status, yet the version was already stamped.
    await database.execute('DROP TABLE customers');
    await database.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        phone TEXT,
        whatsapp TEXT,
        email TEXT,
        address TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        customer_type TEXT NOT NULL,
        service_required TEXT NOT NULL
      )
    ''');
    await database.insert('customers', {
      'uuid': 'customer-uuid-1',
      'name': 'Alice',
      'created_at': now,
      'updated_at': now,
      'customer_type': 'personal',
      'service_required': 'embroidery',
    });

    await DatabaseSchema.upgradeToVersion6(database);

    final columns = await database.rawQuery('PRAGMA table_info(customers)');
    expect(
      columns.any((column) => column['name'] == 'sync_status'),
      isTrue,
    );

    final customers = await database.query('customers');
    expect(customers.single['sync_status'], 'synced');

    // Idempotent: a second run must not throw (duplicate column).
    await DatabaseSchema.upgradeToVersion6(database);
  });
}
