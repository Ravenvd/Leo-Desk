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

  Future<Bill?> getByOrderUuid(String orderUuid) async {
    final db = await _db;
    final maps = await db.query(
      'bills',
      where: 'order_uuid = ?',
      whereArgs: [orderUuid],
      limit: 1,
    );
    return maps.isEmpty ? null : Bill.fromMap(maps.first);
  }

  Future<int> insert({
    required Bill bill,
    required List<BillItem> items,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('A bill must contain at least one item.');
    }

    final db = await _db;

    // Resolve the customer's uuid so the bill stays linked to the
    // customer across devices (local integer ids differ per device).
    var customerUuid = bill.customerUuid;
    if (customerUuid == null) {
      final customers = await db.query(
        'customers',
        columns: ['uuid'],
        where: 'id = ?',
        whereArgs: [bill.customerId],
        limit: 1,
      );
      if (customers.isNotEmpty) {
        customerUuid = customers.first['uuid'] as String;
      }
    }

    final localBill = bill.copyWith(
      syncStatus: 'pending',
      customerUuid: customerUuid,
    );

    return db.transaction((txn) async {
      final billId = await txn.insert('bills', localBill.toMap()..remove('id'));

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

  /// Inserts or updates a bill (with its items) received from sync.
  ///
  /// Returns false when the bill cannot be applied — either because the
  /// owning customer is not present locally yet, or because a locally
  /// modified (pending) bill with the same uuid exists (local wins until
  /// it is pushed).
  Future<bool> upsertFromSync(Bill bill, List<BillItem> items) async {
    final db = await _db;

    final existing = await db.query(
      'bills',
      columns: ['id', 'sync_status'],
      where: 'uuid = ?',
      whereArgs: [bill.uuid],
      limit: 1,
    );

    if (existing.isNotEmpty && existing.first['sync_status'] == 'pending') {
      return false;
    }

    // Resolve the local customer id from the customer uuid.
    int customerId;
    if (bill.customerUuid != null) {
      final customers = await db.query(
        'customers',
        columns: ['id'],
        where: 'uuid = ?',
        whereArgs: [bill.customerUuid],
        limit: 1,
      );
      if (customers.isEmpty) {
        return false;
      }
      customerId = customers.first['id'] as int;
    } else {
      return false;
    }

    // Integer order ids are local to each device. Resolve the order by uuid
    // before storing the bill locally.
    int? orderId;
    if (bill.orderUuid != null) {
      final orders = await db.query(
        'orders',
        columns: ['id'],
        where: 'uuid = ?',
        whereArgs: [bill.orderUuid],
        limit: 1,
      );
      if (orders.isEmpty) {
        return false;
      }
      orderId = orders.first['id'] as int;
    }

    final map = bill
        .copyWith(
          syncStatus: 'synced',
          customerId: customerId,
          orderId: orderId,
        )
        .toMap()
      ..remove('id');

    await db.transaction((txn) async {
      int billId;

      if (existing.isEmpty) {
        billId = await txn.insert('bills', map);
      } else {
        billId = existing.first['id'] as int;
        await txn.update('bills', map, where: 'id = ?', whereArgs: [billId]);
        await txn.delete(
          'bill_items',
          where: 'bill_id = ?',
          whereArgs: [billId],
        );
      }

      for (final item in items) {
        await txn.insert(
          'bill_items',
          item.toMap()
            ..remove('id')
            ..['bill_id'] = billId,
        );
      }
    });

    return true;
  }

  Future<List<Bill>> getPending() async {
    final db = await _db;

    final maps = await db.query(
      'bills',
      where: 'sync_status = ?',
      whereArgs: ['pending'],
    );

    return maps.map(Bill.fromMap).toList();
  }

  /// Removes every bill and bill item. Used by pull-and-replace before
  /// applying the server's dataset.
  Future<void> deleteAll() async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('bill_items');
      await txn.delete('bills');
    });
  }

  Future<int> markSynced(String uuid) async {
    final db = await _db;

    return db.update(
      'bills',
      {'sync_status': 'synced'},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
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

    final maps = await db.query('bills', orderBy: 'bill_date DESC, id DESC');

    return maps.map(Bill.fromMap).toList();
  }
}
