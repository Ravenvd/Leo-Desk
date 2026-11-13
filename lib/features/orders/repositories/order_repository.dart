import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_engine.dart';
import '../models/order.dart';
import '../models/order_item.dart';

class OrderSyncReconciliation {
  final Order order;
  final List<OrderItem> items;
  final String customerUuid;

  const OrderSyncReconciliation({
    required this.order,
    required this.items,
    required this.customerUuid,
  });
}

class OrderRepository {
  final Database? database;

  OrderRepository({this.database});

  Future<Database> get _db async {
    return database ?? await AppDatabase.database;
  }

  Future<int> insert(Order order) async {
    final db = await _db;
    final localOrder = order.copyWith(syncStatus: 'pending');
    return db.insert('orders', localOrder.toMap()..remove('id'));
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
    return db.delete('orders', where: 'id = ?', whereArgs: [id]);
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

  /// Returns the most recent orders for incremental sync reconciliation.
  ///
  /// The sync protocol intentionally works on a bounded recent window rather
  /// than scanning the complete order history on every sync.
  Future<List<Order>> getRecent({int limit = 10}) async {
    if (limit <= 0) return <Order>[];

    final db = await _db;
    final maps = await db.query(
      'orders',
      orderBy: 'updated_at DESC, id DESC',
      limit: limit,
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

  /// Reconciles an Android order against Windows authority and persists
  /// a new order graph atomically. Existing UUIDs are returned unchanged.
  Future<OrderSyncReconciliation> reconcileFromSync(
    Order incomingOrder,
    List<OrderItem> incomingItems, {
    required String customerUuid,
  }) async {
    final db = await _db;

    return db.transaction((txn) async {
      final customers = await txn.query(
        'customers',
        columns: ['id'],
        where: 'uuid = ?',
        whereArgs: [customerUuid],
        limit: 1,
      );
      if (customers.isEmpty) {
        throw StateError('Order customer does not exist on Windows.');
      }

      final incoming = incomingOrder.copyWith(
        customerId: customers.first['id'] as int,
        syncStatus: 'synced',
      );
      final rows = await txn.query('orders');
      final existingOrders = rows.map(Order.fromMap).toList(growable: false);
      final decision = const SyncEngine().reconcileNumberedRecord<Order>(
        incomingRecord: incoming,
        existingRecords: existingOrders,
        uuidOf: (record) => record.uuid,
        numberOf: (record) => record.orderNumber,
        withCanonicalNumber: (record, number) =>
            record.copyWith(orderNumber: number),
      );

      if (!decision.isNewRecord) {
        final canonical = decision.canonicalRecord;
        final canonicalItems = await txn.query(
          'order_items',
          where: 'order_id = ?',
          whereArgs: [canonical.id],
          orderBy: 'id ASC',
        );
        final canonicalCustomer = await txn.query(
          'customers',
          columns: ['uuid'],
          where: 'id = ?',
          whereArgs: [canonical.customerId],
          limit: 1,
        );
        if (canonicalCustomer.isEmpty) {
          throw StateError('Canonical order customer is missing.');
        }
        return OrderSyncReconciliation(
          order: canonical,
          items: canonicalItems.map(OrderItem.fromMap).toList(),
          customerUuid: canonicalCustomer.first['uuid'] as String,
        );
      }

      final canonical = decision.canonicalRecord;
      final orderId = await txn.insert(
        'orders',
        canonical.toMap()..remove('id'),
      );
      for (final item in incomingItems) {
        await txn.insert(
          'order_items',
          item.copyWith(orderId: orderId).toMap()..remove('id'),
        );
      }

      return OrderSyncReconciliation(
        order: canonical.copyWith(id: orderId, syncStatus: 'synced'),
        items: incomingItems
            .map((item) => item.copyWith(orderId: orderId))
            .toList(growable: false),
        customerUuid: customerUuid,
      );
    });
  }

  Future<bool> upsertFromSync(
    Order order,
    List<OrderItem> items, {
    String? customerUuid,
    bool force = false,
  }) async {
    final db = await _db;

    return db.transaction((txn) async {
      final existing = await txn.query(
        'orders',
        columns: ['id', 'sync_status'],
        where: 'uuid = ?',
        whereArgs: [order.uuid],
        limit: 1,
      );

      if (!force &&
          existing.isNotEmpty &&
          existing.first['sync_status'] == 'pending') {
        return false;
      }

      // Never resolve a number conflict by deleting another order or its
      // dependent invoices/bills. A canonical batch can resolve stale local
      // numbering once both UUIDs' Windows records are available.
      final numberOwners = await txn.query(
        'orders',
        columns: ['uuid'],
        where: 'order_number = ? AND uuid != ?',
        whereArgs: [order.orderNumber, order.uuid],
        limit: 1,
      );
      if (numberOwners.isNotEmpty) return false;

      var customerId = order.customerId;
      if (customerUuid != null) {
        final customers = await txn.query(
          'customers',
          columns: ['id'],
          where: 'uuid = ?',
          whereArgs: [customerUuid],
          limit: 1,
        );
        if (customers.isEmpty) return false;
        customerId = customers.first['id'] as int;
      }

      final map = order.copyWith(
        customerId: customerId,
        syncStatus: 'synced',
      ).toMap()..remove('id');
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