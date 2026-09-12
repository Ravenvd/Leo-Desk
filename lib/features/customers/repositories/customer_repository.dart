import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../models/customer.dart';

class CustomerRepository {
  final Database? _database;

  CustomerRepository({this._database});

  Future<Database> get _db async {
    return _database ?? await AppDatabase.database;
  }

  Future<int> insert(Customer customer) async {
    final db = await _db;

    return db.insert(
      'customers',
      customer.toMap(),
    );
  }

Future<void> upsertFromSync(Customer customer) async {
  final db = await _db;

  final existing = await db.query(
    'customers',
    columns: ['id'],
    where: 'uuid = ?',
    whereArgs: [customer.uuid],
    limit: 1,
  );

  if (existing.isEmpty) {
    final map = customer.toMap();
    map.remove('id');

    await db.insert(
      'customers',
      map,
    );
    return;
  }

  final map = customer.toMap();
  map.remove('id');

  await db.update(
    'customers',
    map,
    where: 'uuid = ?',
    whereArgs: [customer.uuid],
  );
}
  Future<List<Customer>> getAll() async {
    final db = await _db;

    final maps = await db.query(
      'customers',
      orderBy: 'name COLLATE NOCASE ASC',
    );

    return maps.map(Customer.fromMap).toList();
  }

  Future<Customer?> getById(int id) async {
    final db = await _db;

    final maps = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) {
      return null;
    }

    return Customer.fromMap(maps.first);
  }

  Future<int> update(Customer customer) async {
    if (customer.id == null) {
      throw ArgumentError('Cannot update a customer without an id.');
    }

    final db = await _db;

    return db.update(
      'customers',
      customer.toMap(),
      where: 'id = ?',
      whereArgs: [customer.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await _db;

    return db.delete(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Customer>> search(String query) async {
    final db = await _db;

    final trimmedQuery = query.trim();

    if (trimmedQuery.isEmpty) {
      return getAll();
    }

    final maps = await db.query(
      'customers',
      where: '''
        name LIKE ?
        OR phone LIKE ?
        OR whatsapp LIKE ?
        OR email LIKE ?
      ''',
      whereArgs: [
        '%$trimmedQuery%',
        '%$trimmedQuery%',
        '%$trimmedQuery%',
        '%$trimmedQuery%',
      ],
      orderBy: 'name COLLATE NOCASE ASC',
    );

    return maps.map(Customer.fromMap).toList();
  }
}