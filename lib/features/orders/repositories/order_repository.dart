import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../models/order.dart';
import '../models/order_item.dart';

class OrderRepository {
  final Database? database;

  OrderRepository({this.database});

  Future<Database> get _db async {
    return database ?? await AppDatabase.database;
  }

  Future<int> insert(Order order) async {
    final db = await _db;
    final localOrder = order.copyWith(syncStatus: 'pending');

    return db.insert(
      'orders',
      localOrder.toMap()..remove('id'),
    );
  }

  Future<int> update(Order order) async {
    if (order.id == null) {
      throw ArgumentError('Cannot update an order without an id.');
    }

    final db = await _db;
    final localOrder = order.copyWith(syncStatus: 'pending');

    return db.update(
      'orders',
      localOrder.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [order.id],
    );
  }

  Future<List<OrderItem>> getItems(int orderId) async {
    final db = await _db;

    final maps = await db.query(
      'order_items',
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'id ASC',
    );

    return maps.map(OrderItem.fromMap).toList();
  }

  Future<int> delete(int id) async {
    final db = await _db;

    return db.delete(
      'orders',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Order?> getById(int id) async {
    final db = await _db;

    final maps = await db.query(
      'orders',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return Order.fromMap(maps.first);
  }

  Future<List<Order>> getAll() async {
    final db = await _db;

    final maps = await db.query(
      'orders',
      orderBy: 'order_date DESC, id DESC',
    );

    return maps.map(Order.fromMap).toList();
  }

  Future<List<Order>> getByCustomer(int customerId) async {
    final db = await _db;

    final maps = await db.query(
      'orders',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'order_date DESC, id DESC',
    );

    return maps.map(Order.fromMap).toList();
  }

  Future<List<Order>> getPending() async {
    final db = await _db;

    final maps = await db.query(
      'orders',
      where: 'sync_status = ?',
      whereArgs: ['pending'],
      orderBy: 'order_date DESC, id DESC',
    );

    return maps.map(Order.fromMap).toList();
  }

  Future<int> markSynced(String uuid) async {
    final db = await _db;

    return db.update(
      'orders',
      {'sync_status': 'synced'},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<bool> upsertFromSync(
    Order order,
    List<OrderItem> items,
  ) async {
    final db = await _db;

    return db.transaction((txn) async {
      final existing = await txn.query(
        'orders',
        columns: ['id', 'sync_status'],
        where: 'uuid = ?',
        whereArgs: [order.uuid],
        limit: 1,
      );

      if (existing.isNotEmpty &&
          existing.first['sync_status'] == 'pending') {
        return false;
      }

      final map = order.copyWith(syncStatus: 'synced').toMap()..remove('id');
      late final int localOrderId;

      if (existing.isEmpty) {
        localOrderId = await txn.insert('orders', map);
      } else {
        localOrderId = existing.first['id'] as int;
        await txn.update(
          'orders',
          map,
          where: 'id = ?',
          whereArgs: [localOrderId],
        );
      }

      await txn.delete(
        'order_items',
        where: 'order_id = ?',
        whereArgs: [localOrderId],
      );

      for (final item in items) {
        final itemMap = item.copyWith(orderId: localOrderId).toMap()
          ..remove('id');
        await txn.insert('order_items', itemMap);
      }

      return true;
    });
  }

  Future<int> updateOrderNumberAndMarkSynced(
    String uuid,
    String orderNumber,
  ) async {
    final db = await _db;
    return db.update(
      'orders',
      {
        'order_number': orderNumber,
        'sync_status': 'synced',
      },
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<void> deleteAll() async {
    final db = await _db;
    await db.delete('orders');
  }
}
