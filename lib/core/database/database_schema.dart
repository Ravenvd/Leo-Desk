import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class DatabaseSchema {
  static const int version = 5;

  static const List<String> createStatements = [
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
      uuid TEXT NOT NULL UNIQUE,
      sync_status TEXT NOT NULL DEFAULT 'synced',
      customer_id INTEGER NOT NULL,
      customer_uuid TEXT,
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
      uuid TEXT NOT NULL UNIQUE,
      bill_id INTEGER NOT NULL,
      description TEXT NOT NULL,
      quantity REAL NOT NULL,
      rate_paise INTEGER NOT NULL,
      amount_paise INTEGER NOT NULL,
      FOREIGN KEY (bill_id) REFERENCES bills(id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE INDEX idx_bills_customer_id
    ON bills(customer_id)
    ''',
    '''
    CREATE INDEX idx_bills_bill_date
    ON bills(bill_date)
    ''',
    '''
    CREATE INDEX idx_bill_items_bill_id
    ON bill_items(bill_id)
    ''',
  ];

  static const List<String> upgradeToVersion3 = [
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
    '''
    CREATE INDEX idx_bills_customer_id
    ON bills(customer_id)
    ''',
    '''
    CREATE INDEX idx_bills_bill_date
    ON bills(bill_date)
    ''',
    '''
    CREATE INDEX idx_bill_items_bill_id
    ON bill_items(bill_id)
    ''',
  ];

  static Future<void> upgradeToVersion4(Database db) async {
    await db.transaction((txn) async {
      await txn.execute('ALTER TABLE customers ADD COLUMN uuid TEXT');

      final customers = await txn.query('customers', columns: ['id']);

      const uuidGenerator = Uuid();

      for (final customer in customers) {
        await txn.update(
          'customers',
          {'uuid': uuidGenerator.v4()},
          where: 'id = ?',
          whereArgs: [customer['id']],
        );
      }

      await txn.execute('''
        CREATE UNIQUE INDEX idx_customers_uuid
        ON customers(uuid)
      ''');
      await txn.execute('''
        ALTER TABLE customers
        ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'synced'
      ''');
    });
  }

  static Future<void> upgradeToVersion5(Database db) async {
    const uuidGenerator = Uuid();

    await db.transaction((txn) async {
      // --- bills: uuid, sync_status, customer_uuid ---
      await txn.execute('ALTER TABLE bills ADD COLUMN uuid TEXT');
      await txn.execute('''
        ALTER TABLE bills
        ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'synced'
      ''');
      await txn.execute('ALTER TABLE bills ADD COLUMN customer_uuid TEXT');

      final bills = await txn.query('bills', columns: ['id']);
      for (final bill in bills) {
        await txn.update(
          'bills',
          {'uuid': uuidGenerator.v4()},
          where: 'id = ?',
          whereArgs: [bill['id']],
        );
      }

      await txn.execute('''
        UPDATE bills
        SET customer_uuid = (
          SELECT uuid FROM customers
          WHERE customers.id = bills.customer_id
        )
      ''');

      await txn.execute('''
        CREATE UNIQUE INDEX idx_bills_uuid
        ON bills(uuid)
      ''');

      // --- bill_items: uuid ---
      await txn.execute('ALTER TABLE bill_items ADD COLUMN uuid TEXT');

      final items = await txn.query('bill_items', columns: ['id']);
      for (final item in items) {
        await txn.update(
          'bill_items',
          {'uuid': uuidGenerator.v4()},
          where: 'id = ?',
          whereArgs: [item['id']],
        );
      }

      await txn.execute('''
        CREATE UNIQUE INDEX idx_bill_items_uuid
        ON bill_items(uuid)
      ''');
    });
  }
}
