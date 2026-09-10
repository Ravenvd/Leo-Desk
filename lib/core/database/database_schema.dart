import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class DatabaseSchema {
  static const int version = 4;

  static const List<String> createStatements = [
    '''
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
      await txn.execute(
        'ALTER TABLE customers ADD COLUMN uuid TEXT',
      );

      final customers = await txn.query(
        'customers',
        columns: ['id'],
      );

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
    });
  }
}