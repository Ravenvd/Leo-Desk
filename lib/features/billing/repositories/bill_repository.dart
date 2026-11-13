import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../models/bill.dart';
import '../models/bill_item.dart';

class BillRepository {
  final Database? database;
  final bool isNumberAuthority;

  /// Windows assigns canonical bill numbers. Android retains a UUID placeholder
  /// until the Windows host returns the canonical record in the next pull.
  BillRepository({this.database, bool? isNumberAuthority})
      : isNumberAuthority = isNumberAuthority ?? Platform.isWindows;

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
      billNumber: 'PENDING-${bill.uuid}',
    );

    return db.transaction((txn) async {
      final billId = await txn.insert('bills', localBill.toMap()..remove('id'));
      if (isNumberAuthority) {
        await txn.update(
          'bills',
          {'bill_number': _formatBillNumber(bill.billDate, billId)},
          where: 'id = ?',
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

      return billId;
    });
  }

  /// Inserts or reconciles a bill received from sync.
  ///
  /// A bill UUID identifies the same bill across devices. When two different
  /// synced bills claim the same order, the earliest creation timestamp wins;
  /// UUID order is the deterministic tie-breaker. Pending local bills are
  /// protected until their push is resolved. Returns false when reconciliation
  /// must be deferred or the incoming bill loses.
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

    // Windows ignores a client-proposed bill number. Existing UUIDs retain
    // their assigned number; new UUIDs receive a number from the Windows row ID.
    final reconciledBill = isNumberAuthority
        ? bill.copyWith(
            billNumber: existingByUuid.isEmpty
                ? 'PENDING-${bill.uuid}'
                : existingByUuid.first['bill_number'] as String,
          )
        : bill;
    final map = reconciledBill
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
        if (!force && conflict.syncStatus == 'pending') {
          // A pending local bill must be pushed before a competing canonical
          // copy can replace it. Defer reconciliation rather than lose edits.
          return false;
        }
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
      final billNumberOwners = isNumberAuthority
          ? <Map<String, Object?>>[]
          : await txn.query(
              'bills',
              columns: ['id', 'uuid', 'sync_status'],
              where: 'bill_number = ? AND uuid != ?',
              whereArgs: [bill.billNumber, bill.uuid],
            );
      final conflictIds = orderConflicts
          .map((row) => row['id'] as int)
          .toSet();
      final unrelatedNumberOwners = billNumberOwners
          .where((owner) => !conflictIds.contains(owner['id'] as int))
          .toList();
      if (unrelatedNumberOwners.any(
        (owner) => !force && owner['sync_status'] == 'pending',
      )) {
        // Never evict an unsynced bill just to free a canonical number.
        return false;
      }

      // A synced local record may still carry a legacy/client-generated
      // number that collides with Windows. Keep the record, but free the
      // canonical number so its own Windows copy can reconcile later.
      for (final owner in unrelatedNumberOwners) {
        await txn.update(
          'bills',
          {'bill_number': 'PENDING-${owner['uuid']}'},
          where: 'id = ?',
          whereArgs: [owner['id']],
        );
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
        if (isNumberAuthority) {
          await txn.update(
            'bills',
            {'bill_number': _formatBillNumber(bill.billDate, billId)},
            where: 'id = ?',
            whereArgs: [billId],
          );
        }
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

  String _formatBillNumber(DateTime billDate, int id) {
    final date = '${billDate.year}'
        '${billDate.month.toString().padLeft(2, '0')}'
        '${billDate.day.toString().padLeft(2, '0')}';
    return 'BILL-$date-${id.toString().padLeft(6, '0')}';
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
