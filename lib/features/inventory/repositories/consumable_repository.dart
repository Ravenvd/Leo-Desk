import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../models/consumable.dart';
import '../models/inventory_activity.dart';
import '../models/thread_spool.dart';

/// Local-first data access for consumables, spools and the stock activity ledger.
///
/// Stock quantities for non-thread supplies are derived from the latest
/// activity's after_quantity. Thread is tracked per spool as a percentage.
class ConsumableRepository {
  final Database? database;

  ConsumableRepository({this.database});

  Future<Database> get _db async => database ?? await AppDatabase.database;

  Future<int> insertConsumable(Consumable consumable) async {
    final db = await _db;
    final now = DateTime.now();
    final local = consumable.copyWith(
      syncStatus: Consumable.syncStatusPending,
      updatedAt: now,
    );
    final map = local.toMap()..remove('id');
    return db.insert('consumables', map);
  }

  Future<int> updateConsumable(Consumable consumable) async {
    if (consumable.id == null) {
      throw ArgumentError('Cannot update a consumable without an id.');
    }
    final db = await _db;
    final local = consumable.copyWith(
      syncStatus: Consumable.syncStatusPending,
      updatedAt: DateTime.now(),
    );
    return db.update(
      'consumables',
      local.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [consumable.id],
    );
  }

  Future<Consumable?> getConsumableById(int id) async {
    final db = await _db;
    final rows = await db.query(
      'consumables',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Consumable.fromMap(rows.first);
  }

  Future<Consumable?> getConsumableByUuid(String uuid) async {
    final db = await _db;
    final rows = await db.query(
      'consumables',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    return rows.isEmpty ? null : Consumable.fromMap(rows.first);
  }

  Future<List<Consumable>> getConsumables({String? category}) async {
    final db = await _db;
    final rows = await db.query(
      'consumables',
      where: category == null ? null : 'category = ?',
      whereArgs: category == null ? null : [category],
      orderBy: 'category COLLATE NOCASE ASC, name COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(Consumable.fromMap).toList();
  }

  Future<List<Consumable>> searchConsumables(String query) async {
    final db = await _db;
    final term = '%${query.trim()}%';
    final rows = await db.query(
      'consumables',
      where: 'name LIKE ? OR category LIKE ? OR colour LIKE ? OR size LIKE ? OR finish LIKE ?',
      whereArgs: [term, term, term, term, term],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Consumable.fromMap).toList();
  }

  Future<int> addThreadSpool({
    required Consumable consumable,
    required double approximateLengthM,
    DateTime? purchaseDate,
    int? purchaseCostPaise,
    String? notes,
  }) async {
    if (consumable.id == null) {
      throw ArgumentError('Save the thread consumable before adding a spool.');
    }
    if (approximateLengthM <= 0) {
      throw ArgumentError.value(approximateLengthM, 'approximateLengthM');
    }

    final db = await _db;
    final now = DateTime.now();
    final spool = ThreadSpool(
      consumableId: consumable.id!,
      consumableUuid: consumable.uuid,
      approximateLengthM: approximateLengthM,
      remainingPercent: 100,
      purchaseDate: purchaseDate,
      purchaseCostPaise: purchaseCostPaise,
      createdAt: now,
      updatedAt: now,
    );

    return db.transaction((txn) async {
      final spoolId = await txn.insert(
        'thread_spools',
        spool.toMap()..remove('id'),
      );
      final activity = InventoryActivity(
        consumableId: consumable.id!,
        consumableUuid: consumable.uuid,
        spoolId: spoolId,
        spoolUuid: spool.uuid,
        activityType: InventoryActivity.purchase,
        quantity: approximateLengthM,
        unit: Consumable.unitMetres,
        totalCostPaise: purchaseCostPaise,
        notes: notes,
        createdAt: now,
        updatedAt: now,
      );
      await txn.insert('inventory_activities', activity.toMap()..remove('id'));
      return spoolId;
    });
  }

  Future<List<ThreadSpool>> getSpools(int consumableId,
      {bool includeEmpty = true}) async {
    final db = await _db;
    final rows = await db.query(
      'thread_spools',
      where: includeEmpty
          ? 'consumable_id = ?'
          : 'consumable_id = ? AND emptied_at IS NULL AND remaining_percent > 0',
      whereArgs: [consumableId],
      orderBy: 'created_at DESC, uuid DESC',
    );
    return rows.map(ThreadSpool.fromMap).toList();
  }

  Future<List<ThreadSpool>> getLowThreadSpools() async {
    final db = await _db;
    final rows = await db.query(
      'thread_spools',
      where: 'emptied_at IS NULL AND remaining_percent < 10',
      orderBy: 'remaining_percent ASC, updated_at ASC',
    );
    return rows.map(ThreadSpool.fromMap).toList();
  }

  Future<int> updateSpoolRemaining({
    required ThreadSpool spool,
    required double remainingPercent,
    int? orderId,
    String? orderUuid,
    String? notes,
  }) async {
    if (spool.id == null) throw ArgumentError('Spool must be saved first.');
    if (spool.isEmpty) throw StateError('An empty spool cannot be updated.');
    if (remainingPercent <= 0 || remainingPercent > spool.remainingPercent) {
      throw ArgumentError.value(
        remainingPercent,
        'remainingPercent',
        'Must be greater than 0 and no more than the current remaining percentage.',
      );
    }

    final db = await _db;
    final now = DateTime.now();
    final activity = InventoryActivity(
      consumableId: spool.consumableId,
      consumableUuid: spool.consumableUuid,
      spoolId: spool.id,
      spoolUuid: spool.uuid,
      orderId: orderId,
      orderUuid: orderUuid,
      activityType: InventoryActivity.threadUsage,
      quantity: spool.approximateLengthM *
          (spool.remainingPercent - remainingPercent) /
          100,
      unit: Consumable.unitMetres,
      beforeQuantity: spool.estimatedRemainingMetres,
      afterQuantity: spool.approximateLengthM * remainingPercent / 100,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );

    return db.transaction((txn) async {
      final updated = await txn.update(
        'thread_spools',
        {
          'remaining_percent': remainingPercent,
          'sync_status': ThreadSpool.syncStatusPending,
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ? AND emptied_at IS NULL AND remaining_percent = ?',
        whereArgs: [spool.id, spool.remainingPercent],
      );
      if (updated == 0) {
        throw StateError('Spool changed since it was loaded. Refresh and retry.');
      }
      await txn.insert('inventory_activities', activity.toMap()..remove('id'));
      return updated;
    });
  }

  Future<void> markSpoolEmpty({
    required ThreadSpool spool,
    required double estimatedWastagePercent,
    String? notes,
  }) async {
    if (spool.id == null) throw ArgumentError('Spool must be saved first.');
    if (spool.isEmpty) throw StateError('Spool is already empty.');
    if (estimatedWastagePercent < 0 || estimatedWastagePercent > spool.remainingPercent) {
      throw ArgumentError.value(
        estimatedWastagePercent,
        'estimatedWastagePercent',
        'Must be between zero and the remaining percentage.',
      );
    }

    final db = await _db;
    final now = DateTime.now();
    final activity = InventoryActivity(
      consumableId: spool.consumableId,
      consumableUuid: spool.consumableUuid,
      spoolId: spool.id,
      spoolUuid: spool.uuid,
      activityType: InventoryActivity.threadExhausted,
      quantity: spool.estimatedRemainingMetres,
      unit: Consumable.unitMetres,
      beforeQuantity: spool.estimatedRemainingMetres,
      afterQuantity: 0,
      estimatedWastagePercent: estimatedWastagePercent,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );

    await db.transaction((txn) async {
      final updated = await txn.update(
        'thread_spools',
        {
          'remaining_percent': 0,
          'emptied_at': now.toIso8601String(),
          'estimated_wastage_percent': estimatedWastagePercent,
          'sync_status': ThreadSpool.syncStatusPending,
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ? AND emptied_at IS NULL',
        whereArgs: [spool.id],
      );
      if (updated == 0) throw StateError('Spool is already empty.');
      await txn.insert('inventory_activities', activity.toMap()..remove('id'));
    });
  }

  /// Current quantity for non-thread consumables, stored in the consumable's
  /// stock unit (g for mass-based supplies, ml for oils, count for pieces).
  Future<double> getCurrentStock(int consumableId) async {
    final db = await _db;
    final rows = await db.query(
      'inventory_activities',
      columns: ['activity_type', 'quantity', 'observed_change', 'after_quantity'],
      where: 'consumable_id = ?',
      whereArgs: [consumableId],
      orderBy: 'created_at ASC, uuid ASC',
    );
    return _calculateStock(rows);
  }

  Future<List<Consumable>> getLowStockConsumables() async {
    final db = await _db;
    final rows = await db.query('consumables', where: 'tracking_type != ?', whereArgs: [Consumable.trackingPercentage], orderBy: 'category COLLATE NOCASE, name COLLATE NOCASE');
    final lowStock = <Consumable>[];
    for (final row in rows) {
      final consumable = Consumable.fromMap(row);
      if (await getCurrentStock(consumable.id!) < consumable.reorderLevel) lowStock.add(consumable);
    }
    return lowStock;
  }

  double _calculateStock(List<Map<String, Object?>> rows) {
    var stock = 0.0;
    for (final row in rows) {
      switch (row['activity_type']) {
        case InventoryActivity.purchase:
        case InventoryActivity.openingStock:
          stock += (row['quantity'] as num?)?.toDouble() ?? 0;
          break;
        case InventoryActivity.stockAdjustment:
          stock += (row['observed_change'] as num?)?.toDouble() ?? 0;
          break;
        case InventoryActivity.stockObservation:
          final observed = row['after_quantity'];
          if (observed != null) stock = (observed as num).toDouble();
          break;
      }
    }
    return stock < 0 && stock > -0.000001 ? 0 : stock;
  }
  /// Adds a purchase or opening balance and records the resulting stock.
  Future<void> recordStockIn({
    required Consumable consumable,
    required double quantity,
    required String activityType,
    int? totalCostPaise,
    String? notes,
  }) async {
    if (consumable.id == null) throw ArgumentError('Save consumable first.');
    if (consumable.trackingType == Consumable.trackingPercentage) {
      throw ArgumentError('Thread stock must be recorded as individual spools.');
    }
    if (quantity <= 0) throw ArgumentError.value(quantity, 'quantity');
    if (activityType != InventoryActivity.purchase &&
        activityType != InventoryActivity.openingStock) {
      throw ArgumentError.value(activityType, 'activityType');
    }

    final db = await _db;
    final now = DateTime.now();
    await db.transaction((txn) async {
      final current = await _currentStockInTransaction(txn, consumable.id!);
      final next = current + quantity;
      final activity = InventoryActivity(
        consumableId: consumable.id!,
        consumableUuid: consumable.uuid,
        activityType: activityType,
        quantity: quantity,
        unit: consumable.stockUnit,
        beforeQuantity: current,
        afterQuantity: next,
        totalCostPaise: totalCostPaise,
        notes: notes,
        createdAt: now,
        updatedAt: now,
      );
      await txn.insert('inventory_activities', activity.toMap()..remove('id'));
    });
  }

  /// Records an observed quantity after weighing/counting; this is not treated
  /// as automatic consumption. A negative observedChange means stock fell.
  Future<void> recordStockObservation({
    required Consumable consumable,
    required double observedQuantity,
    String? notes,
  }) async {
    if (consumable.id == null) throw ArgumentError('Save consumable first.');
    if (consumable.trackingType == Consumable.trackingPercentage) {
      throw ArgumentError('Thread stock is observed per spool.');
    }
    if (observedQuantity < 0) {
      throw ArgumentError.value(observedQuantity, 'observedQuantity');
    }

    final db = await _db;
    final now = DateTime.now();
    await db.transaction((txn) async {
      final previous = await _currentStockInTransaction(txn, consumable.id!);
      final activity = InventoryActivity(
        consumableId: consumable.id!,
        consumableUuid: consumable.uuid,
        activityType: InventoryActivity.stockObservation,
        unit: consumable.stockUnit,
        beforeQuantity: previous,
        afterQuantity: observedQuantity,
        observedChange: observedQuantity - previous,
        notes: notes,
        createdAt: now,
        updatedAt: now,
      );
      await txn.insert('inventory_activities', activity.toMap()..remove('id'));
    });
  }

  Future<void> adjustStock({
    required Consumable consumable,
    required double quantityChange,
    required String notes,
  }) async {
    if (consumable.id == null) throw ArgumentError('Save consumable first.');
    if (consumable.trackingType == Consumable.trackingPercentage) {
      throw ArgumentError('Thread stock is adjusted per spool.');
    }
    if (notes.trim().isEmpty) {
      throw ArgumentError.value(notes, 'notes', 'Explain the adjustment.');
    }

    final db = await _db;
    final now = DateTime.now();
    await db.transaction((txn) async {
      final previous = await _currentStockInTransaction(txn, consumable.id!);
      final next = previous + quantityChange;
      if (next < 0) throw StateError('Stock cannot become negative.');
      final activity = InventoryActivity(
        consumableId: consumable.id!,
        consumableUuid: consumable.uuid,
        activityType: InventoryActivity.stockAdjustment,
        quantity: quantityChange.abs(),
        unit: consumable.stockUnit,
        beforeQuantity: previous,
        afterQuantity: next,
        observedChange: quantityChange,
        notes: notes.trim(),
        createdAt: now,
        updatedAt: now,
      );
      await txn.insert('inventory_activities', activity.toMap()..remove('id'));
    });
  }

  Future<List<InventoryActivity>> getActivityHistory(
    int consumableId, {
    int limit = 100,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'inventory_activities',
      where: 'consumable_id = ?',
      whereArgs: [consumableId],
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(InventoryActivity.fromMap).toList();
  }

  Future<double> _currentStockInTransaction(
    Transaction txn,
    int consumableId,
  ) async {
    final rows = await txn.query(
      'inventory_activities',
      columns: ['activity_type', 'quantity', 'observed_change', 'after_quantity'],
      where: 'consumable_id = ?',
      whereArgs: [consumableId],
      orderBy: 'created_at ASC, uuid ASC',
    );
    return _calculateStock(rows);
  }
  /// Returns pending inventory rows in dependency order for transport.
  Future<List<Map<String, Object?>>> getPendingSyncRecords() async {
    final db = await _db;
    final result = <Map<String, Object?>>[];
    for (final table in ['consumables', 'thread_spools', 'inventory_activities']) {
      final rows = await db.query(table, where: 'sync_status = ?', whereArgs: ['pending'], orderBy: 'created_at ASC, uuid ASC');
      for (final row in rows) {
        final map = Map<String, Object?>.from(row)..remove('id');
        if (table == 'thread_spools') map.remove('consumable_id');
        if (table == 'inventory_activities') { map.remove('consumable_id'); map.remove('spool_id'); map.remove('order_id'); }
        map['record_type'] = table;
        result.add(map);
      }
    }
    return result;
  }

  /// Full Windows inventory snapshot, with relationships represented by UUID.
  Future<List<Map<String, Object?>>> getAllSyncRecords() async {
    final db = await _db;
    final result = <Map<String, Object?>>[];
    for (final table in ['consumables', 'thread_spools', 'inventory_activities']) {
      final rows = await db.query(table, orderBy: 'created_at ASC, uuid ASC');
      for (final row in rows) {
        final map = Map<String, Object?>.from(row)..remove('id');
        if (table == 'thread_spools') map.remove('consumable_id');
        if (table == 'inventory_activities') { map.remove('consumable_id'); map.remove('spool_id'); map.remove('order_id'); }
        map['record_type'] = table;
        result.add(map);
      }
    }
    return result;
  }

  /// Applies one UUID-addressed record. Local integer IDs are always resolved
  /// from relationship UUIDs and are never accepted from another device.
  Future<bool> upsertSyncRecord(Map<String, Object?> incoming, {bool force = false}) async {
    final db = await _db;
    final map = Map<String, Object?>.from(incoming);
    final type = map.remove('record_type') as String?;
    if (!['consumables', 'thread_spools', 'inventory_activities'].contains(type)) throw FormatException('Unknown inventory record type: $type');
    final uuid = map['uuid'] as String;
    final table = type!;
    final existing = await db.query(table, columns: ['id', 'sync_status'], where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    if (existing.isNotEmpty && !force && existing.first['sync_status'] == 'pending') return false;
    if (table == 'thread_spools' || table == 'inventory_activities') {
      final consumableUuid = map['consumable_uuid'] as String;
      final consumables = await db.query('consumables', columns: ['id'], where: 'uuid = ?', whereArgs: [consumableUuid], limit: 1);
      if (consumables.isEmpty) throw StateError('Missing consumable $consumableUuid for inventory sync.');
      map['consumable_id'] = consumables.first['id'];
    }
    if (table == 'inventory_activities') {
      final spoolUuid = map['spool_uuid'] as String?;
      map['spool_id'] = null;
      if (spoolUuid != null) {
        final spools = await db.query('thread_spools', columns: ['id'], where: 'uuid = ?', whereArgs: [spoolUuid], limit: 1);
        if (spools.isEmpty) throw StateError('Missing thread spool $spoolUuid for inventory sync.');
        map['spool_id'] = spools.first['id'];
      }
      final orderUuid = map['order_uuid'] as String?;
      map['order_id'] = null;
      if (orderUuid != null) {
        final orders = await db.query('orders', columns: ['id'], where: 'uuid = ?', whereArgs: [orderUuid], limit: 1);
        // Order history may be outside the currently synchronized order window.
        // Preserve order_uuid and leave the optional local FK unresolved.
        map['order_id'] = orders.isEmpty ? null : orders.first['id'];
      }
    }
    map['sync_status'] = 'synced';
    if (existing.isEmpty) {
      await db.insert(table, map);
    } else {
      await db.update(table, map, where: 'id = ?', whereArgs: [existing.first['id']]);
    }
    return true;
  }

  Future<void> deleteAllForSyncReplacement() async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('inventory_activities');
      await txn.delete('thread_spools');
      await txn.delete('consumables');
    });
  }

  Future<int> markSyncRecordSynced(String table, String uuid) async {
    if (!['consumables', 'thread_spools', 'inventory_activities'].contains(table)) throw ArgumentError.value(table, 'table');
    final db = await _db;
    return db.update(table, {'sync_status': 'synced'}, where: 'uuid = ?', whereArgs: [uuid]);
  }
}
