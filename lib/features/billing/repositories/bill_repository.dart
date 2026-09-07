import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../models/bill.dart';
import '../models/bill_item.dart';

class BillRepository {
  final Database? database;

  BillRepository({this.database});

  Future<Database> get _db async {
    return database ?? await AppDatabase.database;
  }

  Future<int> insert({
    required Bill bill,
    required List<BillItem> items,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('A bill must contain at least one item.');
    }

    final db = await _db;

    return db.transaction((txn) async {
      final billId = await txn.insert(
        'bills',
        bill.toMap()..remove('id'),
      );

      for (final item in items) {
        await txn.insert(
          'bill_items',
          item.toMap()
            ..remove('id')
            ..['bill_id'] = billId,
        );
      }

      return billId;
    });
  }

  Future<Bill?> getById(int id) async {
    final db = await _db;

    final maps = await db.query(
      'bills',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;

    return Bill.fromMap(maps.first);
  }

  Future<List<BillItem>> getItems(int billId) async {
    final db = await _db;

    final maps = await db.query(
      'bill_items',
      where: 'bill_id = ?',
      whereArgs: [billId],
      orderBy: 'id ASC',
    );

    return maps.map(BillItem.fromMap).toList();
  }

  Future<List<Bill>> getForCustomer(int customerId) async {
    final db = await _db;

    final maps = await db.query(
      'bills',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'bill_date DESC, id DESC',
    );

    return maps.map(Bill.fromMap).toList();
  }

  Future<List<Bill>> getAll() async {
    final db = await _db;

    final maps = await db.query(
      'bills',
      orderBy: 'bill_date DESC, id DESC',
    );

    return maps.map(Bill.fromMap).toList();
  }
}