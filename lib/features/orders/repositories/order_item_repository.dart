import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../models/order_item.dart';

class OrderItemRepository {
  final Database? database;

  OrderItemRepository({this.database});

  Future<Database> get _db async {
    return database ?? await AppDatabase.database;
  }

  Future<int> insert(OrderItem item) async {
    final db = await _db;

    return db.insert(
      'order_items',
      item.toMap()..remove('id'),
    );
  }

  Future<int> update(OrderItem item) async {
    if (item.id == null) {
      throw ArgumentError('Cannot update an order item without an id.');
    }

    final db = await _db;

    return db.update(
      'order_items',
      item.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await _db;

    return db.delete(
      'order_items',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<OrderItem?> getById(int id) async {
    final db = await _db;

    final maps = await db.query(
      'order_items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return OrderItem.fromMap(maps.first);
  }

  Future<List<OrderItem>> getByOrder(int orderId) async {
    final db = await _db;

    final maps = await db.query(
      'order_items',
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'id ASC',
    );

    return maps.map(OrderItem.fromMap).toList();
  }

  Future<void> deleteByOrder(int orderId) async {
    final db = await _db;

    await db.delete(
      'order_items',
      where: 'order_id = ?',
      whereArgs: [orderId],
    );
  }
}
