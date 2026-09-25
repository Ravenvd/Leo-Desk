import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class DatabaseSchema {
  static const int version = 12;

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
      updated_at TEXT NOT NULL
    )
    ''',
    '''
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
    CREATE TABLE expenses (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      sync_status TEXT NOT NULL DEFAULT 'synced',
      expense_date TEXT NOT NULL,
      category TEXT NOT NULL,
      description TEXT NOT NULL,
      amount_paise INTEGER NOT NULL DEFAULT 0,
      notes TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
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
      FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE RESTRICT
    )
    ''',
    '''
    CREATE TABLE order_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      order_id INTEGER NOT NULL,
      work_type TEXT NOT NULL,
      garment_type TEXT NOT NULL,
      quantity INTEGER NOT NULL,
      unit_price_paise INTEGER NOT NULL DEFAULT 0,
      notes TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
    )
    ''',
    '''
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
      FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE RESTRICT,
      FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE RESTRICT
    )
    ''',
    '''
    CREATE TABLE invoice_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      invoice_id INTEGER NOT NULL,
      description TEXT NOT NULL,
      quantity REAL NOT NULL,
      rate_paise INTEGER NOT NULL,
      amount_paise INTEGER NOT NULL,
      FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE INDEX idx_invoices_invoice_date
    ON invoices(invoice_date)
    ''',
    '''
    CREATE INDEX idx_invoice_items_invoice_id
    ON invoice_items(invoice_id)
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
    CREATE UNIQUE INDEX idx_bills_order_id
    ON bills(order_id)
    ''',
    '''
    CREATE UNIQUE INDEX idx_bills_order_uuid
    ON bills(order_uuid)
    ''',
    '''
    CREATE INDEX idx_bill_items_bill_id
    ON bill_items(bill_id)
    ''',
    '''
    CREATE INDEX idx_expenses_expense_date
    ON expenses(expense_date)
    ''',
    '''
    CREATE INDEX idx_orders_customer_id
    ON orders(customer_id)
    ''',
    '''
    CREATE INDEX idx_orders_order_date
    ON orders(order_date)
    ''',
    '''
    CREATE INDEX idx_order_items_order_id
    ON order_items(order_id)
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

  /// Repairs databases created by intermediate sync-branch builds that
  /// stamped version 4/5 on a customers table without sync_status.
  /// Idempotent: does nothing when the column already exists.
  static Future<void> upgradeToVersion6(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(customers)');
    final hasSyncStatus = columns.any(
      (column) => column['name'] == 'sync_status',
    );

    if (!hasSyncStatus) {
      await db.execute('''
        ALTER TABLE customers
        ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'synced'
      ''');
    }
  }

  static Future<void> upgradeToVersion7(Database db) async {
    await db.transaction((txn) async {
      await txn.execute('''
        CREATE TABLE expenses (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          uuid TEXT NOT NULL UNIQUE,
          sync_status TEXT NOT NULL DEFAULT 'synced',
          expense_date TEXT NOT NULL,
          category TEXT NOT NULL,
          description TEXT NOT NULL,
          amount_paise INTEGER NOT NULL DEFAULT 0,
          notes TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      await txn.execute('''
        CREATE INDEX idx_expenses_expense_date
        ON expenses(expense_date)
      ''');
    });
  }

  static Future<void> upgradeToVersion8(Database db) async {
    await db.transaction((txn) async {
      await txn.execute('''
        CREATE TABLE orders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          uuid TEXT NOT NULL UNIQUE,
          sync_status TEXT NOT NULL DEFAULT 'synced',
          order_number TEXT NOT NULL UNIQUE,
          customer_id INTEGER NOT NULL,
          order_date TEXT NOT NULL,
          expected_delivery_date TEXT NOT NULL,
          stitching_required INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'New',
          notes TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE RESTRICT
        )
      ''');

      await txn.execute('''
        CREATE TABLE order_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          uuid TEXT NOT NULL UNIQUE,
          order_id INTEGER NOT NULL,
          work_type TEXT NOT NULL,
          garment_type TEXT NOT NULL,
          quantity INTEGER NOT NULL,
          unit_price_paise INTEGER NOT NULL DEFAULT 0,
          notes TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
        )
      ''');

      await txn.execute('''
        CREATE INDEX idx_orders_customer_id
        ON orders(customer_id)
      ''');
      await txn.execute('''
        CREATE INDEX idx_orders_order_date
        ON orders(order_date)
      ''');
      await txn.execute('''
        CREATE INDEX idx_order_items_order_id
        ON order_items(order_id)
      ''');
    });
  }

  static Future<void> upgradeToVersion9(Database db) async {
    await db.execute('''
      ALTER TABLE orders
      ADD COLUMN stitching_price_paise INTEGER NOT NULL DEFAULT 0
    ''');
  }


  static Future<void> upgradeToVersion11(Database db) async {
    await db.transaction((txn) async {
      await txn.execute('ALTER TABLE bills ADD COLUMN order_id INTEGER');
      await txn.execute('ALTER TABLE bills ADD COLUMN order_uuid TEXT');

      await txn.execute('''
        CREATE UNIQUE INDEX idx_bills_order_id
        ON bills(order_id)
      ''');
      await txn.execute('''
        CREATE UNIQUE INDEX idx_bills_order_uuid
        ON bills(order_uuid)
      ''');
    });
  }


  static Future<void> upgradeToVersion12(Database db) async {
    await db.transaction((txn) async {
      final columns = await txn.rawQuery('PRAGMA table_info(customers)');
      final columnNames = columns
          .map((column) => column['name'] as String?)
          .whereType<String>()
          .toSet();

      // Be tolerant of databases created by intermediate builds. Some of
      // those databases already have the v12 customer schema even though
      // their recorded version still triggers this migration.
      if (columnNames.contains('customer_type')) {
        await txn.execute(
          'ALTER TABLE customers DROP COLUMN customer_type',
        );
      }

      if (columnNames.contains('service_required')) {
        await txn.execute(
          'ALTER TABLE customers DROP COLUMN service_required',
        );
      }
    });
  }

  static Future<void> upgradeToVersion10(Database db) async {
    await db.transaction((txn) async {
      await txn.execute('''
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
          FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE RESTRICT,
          FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE RESTRICT
        )
      ''');
      await txn.execute('''
        CREATE TABLE invoice_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          uuid TEXT NOT NULL UNIQUE,
          invoice_id INTEGER NOT NULL,
          description TEXT NOT NULL,
          quantity REAL NOT NULL,
          rate_paise INTEGER NOT NULL,
          amount_paise INTEGER NOT NULL,
          FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE
        )
      ''');
      await txn.execute('''
        CREATE INDEX idx_invoices_invoice_date
        ON invoices(invoice_date)
      ''');
      await txn.execute('''
        CREATE INDEX idx_invoice_items_invoice_id
        ON invoice_items(invoice_id)
      ''');
    });
  }
}