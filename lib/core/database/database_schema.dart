class DatabaseSchema {
  static const int version = 1;

static const String customers = '''
  CREATE TABLE customers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    phone TEXT,
    whatsapp TEXT,
    email TEXT,
    address TEXT,
    notes TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
''';

  static const String jobs = '''
    CREATE TABLE jobs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER NOT NULL,
      job_number TEXT NOT NULL UNIQUE,
      title TEXT NOT NULL,
      description TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      deadline TEXT,
      notes TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (customer_id) REFERENCES customers (id)
    )
  ''';

  static const String jobItems = '''
    CREATE TABLE job_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      job_id INTEGER NOT NULL,
      description TEXT NOT NULL,
      quantity REAL NOT NULL DEFAULT 1,
      unit TEXT NOT NULL DEFAULT 'pcs',
      rate REAL NOT NULL DEFAULT 0,
      amount REAL NOT NULL DEFAULT 0,
      notes TEXT,
      FOREIGN KEY (job_id) REFERENCES jobs (id) ON DELETE CASCADE
    )
  ''';

  static const String quotations = '''
    CREATE TABLE quotations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER NOT NULL,
      quotation_number TEXT NOT NULL UNIQUE,
      quotation_date TEXT NOT NULL,
      valid_until TEXT,
      status TEXT NOT NULL DEFAULT 'draft',
      subtotal REAL NOT NULL DEFAULT 0,
      discount REAL NOT NULL DEFAULT 0,
      tax REAL NOT NULL DEFAULT 0,
      total REAL NOT NULL DEFAULT 0,
      notes TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (customer_id) REFERENCES customers (id)
    )
  ''';

  static const String quotationItems = '''
    CREATE TABLE quotation_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      quotation_id INTEGER NOT NULL,
      description TEXT NOT NULL,
      quantity REAL NOT NULL DEFAULT 1,
      unit TEXT NOT NULL DEFAULT 'pcs',
      rate REAL NOT NULL DEFAULT 0,
      amount REAL NOT NULL DEFAULT 0,
      FOREIGN KEY (quotation_id) REFERENCES quotations (id) ON DELETE CASCADE
    )
  ''';

  static const String invoices = '''
    CREATE TABLE invoices (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER NOT NULL,
      invoice_number TEXT NOT NULL UNIQUE,
      invoice_date TEXT NOT NULL,
      due_date TEXT,
      status TEXT NOT NULL DEFAULT 'unpaid',
      subtotal REAL NOT NULL DEFAULT 0,
      discount REAL NOT NULL DEFAULT 0,
      tax REAL NOT NULL DEFAULT 0,
      total REAL NOT NULL DEFAULT 0,
      notes TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (customer_id) REFERENCES customers (id)
    )
  ''';

  static const String invoiceItems = '''
    CREATE TABLE invoice_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_id INTEGER NOT NULL,
      description TEXT NOT NULL,
      quantity REAL NOT NULL DEFAULT 1,
      unit TEXT NOT NULL DEFAULT 'pcs',
      rate REAL NOT NULL DEFAULT 0,
      amount REAL NOT NULL DEFAULT 0,
      FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE
    )
  ''';

  static const String payments = '''
    CREATE TABLE payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER NOT NULL,
      invoice_id INTEGER,
      amount REAL NOT NULL,
      payment_date TEXT NOT NULL,
      payment_method TEXT NOT NULL DEFAULT 'cash',
      reference TEXT,
      notes TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY (customer_id) REFERENCES customers (id),
      FOREIGN KEY (invoice_id) REFERENCES invoices (id)
    )
  ''';

  static const String labourers = '''
    CREATE TABLE labourers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      phone TEXT,
      address TEXT,
      notes TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''';

  static const String labourPayments = '''
    CREATE TABLE labour_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      labourer_id INTEGER NOT NULL,
      job_id INTEGER,
      amount REAL NOT NULL,
      payment_date TEXT NOT NULL,
      notes TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY (labourer_id) REFERENCES labourers (id),
      FOREIGN KEY (job_id) REFERENCES jobs (id)
    )
  ''';

  static const String inventoryItems = '''
    CREATE TABLE inventory_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      category TEXT,
      sku TEXT,
      unit TEXT NOT NULL DEFAULT 'pcs',
      quantity REAL NOT NULL DEFAULT 0,
      minimum_quantity REAL NOT NULL DEFAULT 0,
      cost_per_unit REAL NOT NULL DEFAULT 0,
      notes TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''';

  static const String inventoryTransactions = '''
    CREATE TABLE inventory_transactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      inventory_item_id INTEGER NOT NULL,
      type TEXT NOT NULL,
      quantity REAL NOT NULL,
      transaction_date TEXT NOT NULL,
      reference TEXT,
      notes TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY (inventory_item_id) REFERENCES inventory_items (id)
    )
  ''';

  static const List<String> createStatements = [
    customers,
    jobs,
    jobItems,
    quotations,
    quotationItems,
    invoices,
    invoiceItems,
    payments,
    labourers,
    labourPayments,
    inventoryItems,
    inventoryTransactions,
  ];
}