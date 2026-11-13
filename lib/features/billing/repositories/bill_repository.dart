import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_engine.dart';
import '../models/bill.dart';
import '../models/bill_item.dart';

class BillSyncReconciliation {
  final Bill bill;
  final List<BillItem> items;

  const BillSyncReconciliation({
    required this.bill,
    required this.items,
  });
}

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

  /// Reconciles a pushed bill on Windows and returns the complete canonical
  /// graph. UUID wins over all incoming fields; distinct bill-number
  /// collisions receive a server-assigned suffix.
  Future<BillSyncReconciliation> reconcileFromSync(
    Bill incomingBill,
    List<BillItem> incomingItems,
  ) async {
    final db = await _db;

    return db.transaction((txn) async {
      final rows = await txn.query('bills');
      final existingBills = rows.map(Bill.fromMap).toList(growable: false);
      final engine = const SyncEngine();

      final identity = engine.reconcileNumberedRecord<Bill>(
        incomingRecord: incomingBill,
        existingRecords: existingBills,
        uuidOf: (record) => record.uuid,
        numberOf: (record) => record.billNumber,
        withCanonicalNumber: (record, number) =>
            record.copyWith(billNumber: number),
      );

      if (!identity.isNewRecord) {
        final canonical = identity.canonicalRecord;
        final itemRows = await txn.query(
          'bill_items',
          where: 'bill_id = ?',
          whereArgs: [canonical.id],
          orderBy: 'id ASC',
        );
        return BillSyncReconciliation(
          bill: canonical,
          items: itemRows.map(BillItem.fromMap).toList(growable: false),
        );
      }

      if (incomingItems.isEmpty) {
        throw StateError('A bill must contain at least one item.');
      }
      final customerUuid = incomingBill.customerUuid;
      if (customerUuid == null || customerUuid.trim().isEmpty) {
        throw StateError('Bill customer UUID is required.');
      }
      final customers = await txn.query(
        'customers',
        columns: ['id'],
        where: 'uuid = ?',
        whereArgs: [customerUuid],
        limit: 1,
      );
      if (customers.isEmpty) {
        throw StateError('Bill customer does not exist on Windows.');
      }

      int? orderId;
      if (incomingBill.orderUuid != null) {
        final orders = await txn.query(
          'orders',
          columns: ['id'],
          where: 'uuid = ?',
          whereArgs: [incomingBill.orderUuid],
          limit: 1,
        );
        if (orders.isEmpty) {
          throw StateError('Bill order does not exist on Windows.');
        }
        orderId = orders.first['id'] as int;

        // The schema permits one bill per order. Do not replace or delete a
        // different UUID's bill graph to satisfy this natural key.
        final orderOwners = await txn.query(
          'bills',
          columns: ['uuid'],
          where: 'order_uuid = ? AND uuid != ?',
          whereArgs: [incomingBill.orderUuid, incomingBill.uuid],
          limit: 1,
        );
        if (orderOwners.isNotEmpty) {
          throw StateError('A different bill already exists for this order.');
        }
      }

      final incoming = incomingBill.copyWith(
        customerId: customers.first['id'] as int,
        orderId: orderId,
        syncStatus: 'synced',
      );
      final decision = engine.reconcileNumberedRecord<Bill>(
        incomingRecord: incoming,
        existingRecords: existingBills,
        uuidOf: (record) => record.uuid,
        numberOf: (record) => record.billNumber,
        withCanonicalNumber: (record, number) =>
            record.copyWith(billNumber: number),
      );
      final canonical = decision.canonicalRecord;
      final billId = await txn.insert(
        'bills',
        canonical.toMap()..remove('id'),
      );

      for (final item in incomingItems) {
        await txn.insert(
          'bill_items',
          item.toMap()
            ..remove('id')
            ..['bill_id'] = billId,
        );
      }

      final canonicalItems = await txn.query(
        'bill_items',
        where: 'bill_id = ?',
        whereArgs: [billId],
        orderBy: 'id ASC',
      );
      return BillSyncReconciliation(
        bill: canonical.copyWith(id: billId, syncStatus: 'synced'),
        items: canonicalItems.map(BillItem.fromMap).toList(growable: false),
      );
    });
  }

  /// Applies a Windows canonical bill locally. It never removes a distinct
  /// bill to resolve a number or one-bill-per-order conflict.
  Future<bool> upsertFromSync(
    Bill bill,
    List<BillItem> items, {
    bool force = false,
  }) async {
    final db = await _db;

    return db.transaction((txn) async {
      final existing = await txn.query(
        'bills',
        columns: ['id', 'sync_status'],
        where: 'uuid = ?',
        whereArgs: [bill.uuid],
        limit: 1,
      );

      if (!force &&
          existing.isNotEmpty &&
          existing.first['sync_status'] == 'pending') {
        return false;
      }
      if (bill.customerUuid == null) return false;

      final customers = await txn.query(
        'customers',
        columns: ['id'],
        where: 'uuid = ?',
        whereArgs: [bill.customerUuid],
        limit: 1,
      );
      if (customers.isEmpty) return false;

      int? orderId;
      if (bill.orderUuid != null) {
        final orders = await txn.query(
          'orders',
          columns: ['id'],
          where: 'uuid = ?',
          whereArgs: [bill.orderUuid],
          limit: 1,
        );
        if (orders.isEmpty) return false;
        orderId = orders.first['id'] as int;

        final orderOwners = await txn.query(
          'bills',
          columns: ['uuid'],
          where: 'order_uuid = ? AND uuid != ?',
          whereArgs: [bill.orderUuid, bill.uuid],
          limit: 1,
        );
        if (orderOwners.isNotEmpty) return false;
      }

      final numberOwners = await txn.query(
        'bills',
        columns: ['uuid'],
        where: 'bill_number = ? AND uuid != ?',
        whereArgs: [bill.billNumber, bill.uuid],
        limit: 1,
      );
      if (numberOwners.isNotEmpty) return false;

      final map = bill.copyWith(
        syncStatus: 'synced',
        customerId: customers.first['id'] as int,
        orderId: orderId,
      ).toMap()..remove('id');

      late final int billId;
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
      return true;
    });
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
