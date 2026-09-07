class DatabaseSchema {
  static const int version = 2;

  static const List<String> createStatements = [
    '''
    CREATE TABLE customers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
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
  ];
}