import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:leo_desk/core/database/database_schema.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<Database> currentDatabase() => openDatabase(
        inMemoryDatabasePath,
        version: DatabaseSchema.version,
        onCreate: (db, version) async {
          for (final statement in DatabaseSchema.createStatements) {
            await db.execute(statement);
          }
        },
      );

  test('v15 schema creates consumables, thread spools and activity ledger', () async {
    final db = await currentDatabase();

    final consumableColumns = await db.rawQuery('PRAGMA table_info(consumables)');
    expect(consumableColumns.map((column) => column['name']), containsAll([
      'id', 'uuid', 'sync_status', 'category', 'name', 'size', 'finish',
      'colour', 'tracking_type', 'stock_unit', 'reorder_level',
      'default_pack_quantity', 'created_at', 'updated_at',
    ]));

    final spoolColumns = await db.rawQuery('PRAGMA table_info(thread_spools)');
    expect(spoolColumns.map((column) => column['name']), containsAll([
      'id', 'uuid', 'sync_status', 'consumable_id', 'consumable_uuid',
      'approximate_length_m', 'remaining_percent', 'purchase_date',
      'purchase_cost_paise', 'emptied_at', 'estimated_wastage_percent',
      'created_at', 'updated_at',
    ]));

    final activityColumns =
        await db.rawQuery('PRAGMA table_info(inventory_activities)');
    expect(activityColumns.map((column) => column['name']), containsAll([
      'id', 'uuid', 'sync_status', 'consumable_id', 'consumable_uuid',
      'spool_id', 'spool_uuid', 'order_id', 'order_uuid', 'activity_type',
      'quantity', 'unit', 'before_quantity', 'after_quantity',
      'observed_change', 'total_cost_paise', 'estimated_wastage_percent',
      'notes', 'created_at', 'updated_at',
    ]));

    await db.close();
  });

  test('v14 to v15 migration creates the consumables schema', () async {
    final path = '${Directory.systemTemp.path}/leo_desk_consumables_v14_${DateTime.now().microsecondsSinceEpoch}.db';

    final old = await openDatabase(
      path,
      version: 14,
      onCreate: (db, version) async {
        for (final statement in DatabaseSchema.createStatements) {
          if (statement.contains('consumables') ||
              statement.contains('thread_spools') ||
              statement.contains('inventory_activities')) {
            continue;
          }
          await db.execute(statement);
        }
      },
    );
    await old.close();

    try {
      final db = await openDatabase(
        path,
        version: DatabaseSchema.version,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 15) {
            await DatabaseSchema.upgradeToVersion15(db);
          }
        },
      );

      expect(await db.getVersion(), 15);
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final names = tables.map((row) => row['name']).toSet();
      expect(names, containsAll([
        'consumables',
        'thread_spools',
        'inventory_activities',
      ]));

      await db.close();
    } finally {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  });

  test('consumable records preserve sync identity and flexible material metadata',
      () async {
    final db = await currentDatabase();

    await db.insert('consumables', {
      'uuid': 'thread-black-001',
      'sync_status': 'pending',
      'category': 'Embroidery thread',
      'name': 'Embroidery Thread',
      'colour': '1234',
      'tracking_type': 'percentage',
      'stock_unit': 'm',
      'reorder_level': 10,
      'default_pack_quantity': 2000,
      'created_at': '2026-10-04T10:00:00.000',
      'updated_at': '2026-10-04T10:00:00.000',
    });

    final rows = await db.query(
      'consumables',
      where: 'uuid = ?',
      whereArgs: ['thread-black-001'],
    );

    expect(rows, hasLength(1));
    expect(rows.single['uuid'], 'thread-black-001');
    expect(rows.single['sync_status'], 'pending');
    expect(rows.single['colour'], '1234');
    expect(rows.single['tracking_type'], 'percentage');
    expect(rows.single['default_pack_quantity'], 2000);

    await db.close();
  });

  test('thread spool and activity records support order-linked estimated usage',
      () async {
    final db = await currentDatabase();

    final customerId = await db.insert('customers', {
      'uuid': 'customer-inventory-001',
      'sync_status': 'synced',
      'name': 'Inventory Test Customer',
      'created_at': '2026-10-04T10:00:00.000',
      'updated_at': '2026-10-04T10:00:00.000',
    });

    final consumableId = await db.insert('consumables', {
      'uuid': 'thread-red-001',
      'sync_status': 'synced',
      'category': 'Embroidery thread',
      'name': 'Embroidery Thread',
      'colour': '204',
      'tracking_type': 'percentage',
      'stock_unit': 'm',
      'reorder_level': 10,
      'default_pack_quantity': 2000,
      'created_at': '2026-10-04T10:00:00.000',
      'updated_at': '2026-10-04T10:00:00.000',
    });

    final spoolId = await db.insert('thread_spools', {
      'uuid': 'spool-red-001',
      'sync_status': 'pending',
      'consumable_id': consumableId,
      'consumable_uuid': 'thread-red-001',
      'approximate_length_m': 2000,
      'remaining_percent': 100,
      'purchase_date': '2026-10-04',
      'purchase_cost_paise': 12500,
      'created_at': '2026-10-04T10:00:00.000',
      'updated_at': '2026-10-04T10:00:00.000',
    });

    final orderId = await db.insert('orders', {
      'uuid': 'order-inventory-001',
      'sync_status': 'synced',
      'order_number': 'ORD-INV-001',
      'customer_id': customerId,
      'order_date': '2026-10-04T10:00:00.000',
      'expected_delivery_date': '2026-10-05T10:00:00.000',
      'stitching_required': 0,
      'stitching_price_paise': 0,
      'status': 'New',
      'created_at': '2026-10-04T10:00:00.000',
      'updated_at': '2026-10-04T10:00:00.000',
    });

    await db.insert('inventory_activities', {
      'uuid': 'activity-thread-001',
      'sync_status': 'pending',
      'consumable_id': consumableId,
      'consumable_uuid': 'thread-red-001',
      'spool_id': spoolId,
      'spool_uuid': 'spool-red-001',
      'order_id': orderId,
      'order_uuid': 'order-inventory-001',
      'activity_type': 'thread_usage',
      'quantity': 180,
      'unit': 'm',
      'notes': 'Approximate design usage',
      'created_at': '2026-10-04T10:00:00.000',
      'updated_at': '2026-10-04T10:00:00.000',
    });

    final activities = await db.query(
      'inventory_activities',
      where: 'uuid = ?',
      whereArgs: ['activity-thread-001'],
    );

    expect(activities, hasLength(1));
    expect(activities.single['spool_uuid'], 'spool-red-001');
    expect(activities.single['order_uuid'], 'order-inventory-001');
    expect(activities.single['quantity'], 180);
    expect(activities.single['unit'], 'm');

    await db.close();
  });
}
