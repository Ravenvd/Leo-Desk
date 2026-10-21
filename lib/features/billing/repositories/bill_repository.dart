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

  /// Inserts or reconciles a bill received from sync.
  ///
  /// A bill UUID identifies the same bill across devices. When two different
  /// bills claim the same order, the earliest creation timestamp wins; UUID
  /// order is the deterministic tie-breaker. Sync status never overrides this
  /// rule. Returns false when the incoming bill loses or its dependencies are
  /// not available locally.
  Future<bool> upsertFromSync(
    Bill bill,
    List<BillItem> items, {
    bool force = false,
  }) async {
    final db = await _db;

    final existingByUuid = await db.query(
      'bills',
      where: 'uuid = ?',
      whereArgs: [bill.uuid],
      limit: 1,
    );

    // A pending copy with the same UUID is the same bill, not a competing
    // bill. Keep local edits until they have been pushed successfully.
    if (!force &&
        existingByUuid.isNotEmpty &&
        existingByUuid.first['sync_status'] == 'pending') {
      return false;
    }

    // Resolve local foreign keys before attempting to apply the incoming bill.
    int customerId;
    if (bill.customerUuid != null) {
      final customers = await db.query(
        'customers',
        columns: ['id'],
        where: 'uuid = ?',
        whereArgs: [bill.customerUuid],
        limit: 1,
      );
      if (customers.isEmpty) return false;
      customerId = customers.first['id'] as int;
    } else {
      return false;
    }

    int? orderId;
    if (bill.orderUuid != null) {
      final orders = await db.query(
        'orders',
        columns: ['id'],
        where: 'uuid = ?',
        whereArgs: [bill.orderUuid],
        limit: 1,
      );
      if (orders.isEmpty) return false;
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

    return db.transaction((txn) async {
      final sameUuid = await txn.query(
        'bills',
        where: 'uuid = ?',
        whereArgs: [bill.uuid],
        limit: 1,
      );

      if (!force &&
          sameUuid.isNotEmpty &&
          sameUuid.first['sync_status'] == 'pending') {
        return false;
      }

      // A legacy or independently-created bill can have a different UUID but
      // claim the same order. Resolve that conflict by creation time, never by
      // which device happens to sync first or by sync_status.
      final orderConflicts = bill.orderUuid == null
          ? <Map<String, Object?>>[]
          : await txn.query(
              'bills',
              where: 'order_uuid = ? AND uuid != ?',
              whereArgs: [bill.orderUuid, bill.uuid],
            );

      for (final conflictMap in orderConflicts) {
        final conflict = Bill.fromMap(conflictMap);
        if (_compareBillPriority(bill, conflict) >= 0) {
          // ignore: avoid_print
          print(
            'Bill sync conflict: keeping ${conflict.uuid} '
            '(${conflict.createdAt.toIso8601String()}) over '
            '${bill.uuid} (${bill.createdAt.toIso8601String()}) '
            'for order ${bill.orderUuid}.',
          );
          return false;
        }
      }

      // bill_number is also globally unique. Never delete a bill belonging to
      // another order just to make room for an incoming number.
      final billNumberOwners = await txn.query(
        'bills',
        columns: ['id', 'uuid'],
        where: 'bill_number = ? AND uuid != ?',
        whereArgs: [bill.billNumber, bill.uuid],
      );
      final conflictIds = orderConflicts
          .map((row) => row['id'] as int)
          .toSet();
      if (billNumberOwners.any(
        (owner) => !conflictIds.contains(owner['id'] as int),
      )) {
        // ignore: avoid_print
        print(
          'Bill sync conflict: bill number ${bill.billNumber} is already '
          'used by a bill for another order; incoming bill ${bill.uuid} '
          'was not applied.',
        );
        return false;
      }

      // Remove losing copies and their items in the same transaction. The
      // incoming bill then retains its own UUID and bill number as the winner.
      for (final conflictMap in orderConflicts) {
        final conflictId = conflictMap['id'] as int;
        await txn.delete(
          'bill_items',
          where: 'bill_id = ?',
          whereArgs: [conflictId],
        );
        await txn.delete('bills', where: 'id = ?', whereArgs: [conflictId]);
      }

      int billId;
      if (sameUuid.isEmpty) {
        billId = await txn.insert('bills', map);
      } else {
        billId = sameUuid.first['id'] as int;
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

  /// Returns negative when [left] wins, positive when [right] wins.
  /// UUID comparison guarantees identical resolution when timestamps match.
  int _compareBillPriority(Bill left, Bill right) {
    final timestampComparison = left.createdAt.compareTo(right.createdAt);
    if (timestampComparison != 0) return timestampComparison;
    return left.uuid.compareTo(right.uuid);
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
