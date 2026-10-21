import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:leo_desk/core/database/database_schema.dart';
import 'package:leo_desk/features/inventory/models/consumable.dart';
import 'package:leo_desk/features/inventory/models/inventory_activity.dart';
import 'package:leo_desk/features/inventory/repositories/consumable_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<Database> openTestDb() => openDatabase(
        inMemoryDatabasePath,
        version: DatabaseSchema.version,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          for (final statement in DatabaseSchema.createStatements) {
            await db.execute(statement);
          }
        },
      );

  Consumable item({
    required String category,
    required String name,
    required String trackingType,
    required String unit,
    double reorder = 0,
    double? pack,
  }) {
    final now = DateTime(2026, 10, 21);
    return Consumable(
      category: category,
      name: name,
      trackingType: trackingType,
      stockUnit: unit,
      reorderLevel: reorder,
      defaultPackQuantity: pack,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('creates and retrieves consumables with metadata', () async {
    final db = await openTestDb();
    final repository = ConsumableRepository(database: db);
    final model = item(
      category: Consumable.categoryBeads,
      name: 'Cut beads',
      trackingType: Consumable.trackingQuantity,
      unit: Consumable.unitGrams,
      reorder: 200,
      pack: 500,
    ).copyWith(size: '2.5mm', finish: 'Cut', colour: 'Gold');

    final id = await repository.insertConsumable(model);
    final loaded = await repository.getConsumableById(id);

    expect(loaded, isNotNull);
    expect(loaded!.uuid, model.uuid);
    expect(loaded.syncStatus, Consumable.syncStatusPending);
    expect(loaded.size, '2.5mm');
    expect(loaded.finish, 'Cut');
    expect(loaded.colour, 'Gold');
    expect(loaded.defaultPackQuantity, 500);
    expect((await repository.getConsumables(category: Consumable.categoryBeads)), hasLength(1));
    expect((await repository.searchConsumables('gold')), hasLength(1));
    await db.close();
  });

  test('stock purchases add to current stock and create activity history', () async {
    final db = await openTestDb();
    final repository = ConsumableRepository(database: db);
    final model = item(
      category: Consumable.categoryBeads,
      name: 'Gold beads',
      trackingType: Consumable.trackingQuantity,
      unit: Consumable.unitGrams,
      reorder: 200,
    );
    final id = await repository.insertConsumable(model);
    final saved = (await repository.getConsumableById(id))!;

    await repository.recordStockIn(
      consumable: saved,
      quantity: 500,
      activityType: InventoryActivity.openingStock,
    );
    await repository.recordStockIn(
      consumable: saved,
      quantity: 250,
      activityType: InventoryActivity.purchase,
      totalCostPaise: 12500,
    );

    expect(await repository.getCurrentStock(id), 750);
    final history = await repository.getActivityHistory(id);
    expect(history, hasLength(2));
    expect(history.first.activityType, InventoryActivity.purchase);
    expect(history.first.beforeQuantity, 500);
    expect(history.first.afterQuantity, 750);
    await db.close();
  });

  test('observed stock records the difference without auto-consuming stock', () async {
    final db = await openTestDb();
    final repository = ConsumableRepository(database: db);
    final model = item(
      category: Consumable.categoryStabilizers,
      name: 'Tear-away',
      trackingType: Consumable.trackingQuantity,
      unit: Consumable.unitGrams,
      reorder: 200,
    );
    final id = await repository.insertConsumable(model);
    final saved = (await repository.getConsumableById(id))!;

    await repository.recordStockIn(
      consumable: saved,
      quantity: 1000,
      activityType: InventoryActivity.openingStock,
    );
    await repository.recordStockObservation(
      consumable: saved,
      observedQuantity: 760,
      notes: 'After several projects',
    );

    expect(await repository.getCurrentStock(id), 760);
    final history = await repository.getActivityHistory(id);
    expect(history.first.activityType, InventoryActivity.stockObservation);
    expect(history.first.observedChange, -240);
    await db.close();
  });

  test('thread spool remaining and exhausted events are recorded', () async {
    final db = await openTestDb();
    final repository = ConsumableRepository(database: db);
    final model = item(
      category: Consumable.categoryEmbroideryThread,
      name: 'Black thread',
      trackingType: Consumable.trackingPercentage,
      unit: Consumable.unitMetres,
      reorder: 10,
      pack: 2000,
    );
    final id = await repository.insertConsumable(model);
    final saved = (await repository.getConsumableById(id))!;
    final spoolId = await repository.addThreadSpool(
      consumable: saved,
      approximateLengthM: 2000,
    );
    var spool = (await repository.getSpools(id)).single;

    expect(spool.id, spoolId);
    expect(spool.estimatedRemainingMetres, 2000);
    await repository.updateSpoolRemaining(spool: spool, remainingPercent: 8);
    spool = (await repository.getSpools(id)).single;
    expect(spool.isLow, isTrue);
    expect(spool.estimatedRemainingMetres, 160);
    expect(await repository.getLowThreadSpools(), hasLength(1));

    await repository.markSpoolEmpty(
      spool: spool,
      estimatedWastagePercent: 3,
      notes: 'Short end discarded',
    );
    spool = (await repository.getSpools(id)).single;
    expect(spool.isEmpty, isTrue);
    expect(spool.remainingPercent, 0);
    expect(spool.estimatedWastagePercent, 3);
    expect(await repository.getLowThreadSpools(), isEmpty);

    final history = await repository.getActivityHistory(id);
    expect(history.map((activity) => activity.activityType), containsAll([
      InventoryActivity.purchase,
      InventoryActivity.threadUsage,
      InventoryActivity.threadExhausted,
    ]));
    await db.close();
  });

  test('low stock alerts exclude thread and respect reorder thresholds', () async {
    final db = await openTestDb();
    final repository = ConsumableRepository(database: db);
    final beads = item(
      category: Consumable.categoryBeads,
      name: 'Silver beads',
      trackingType: Consumable.trackingQuantity,
      unit: Consumable.unitGrams,
      reorder: 200,
    );
    final beadsId = await repository.insertConsumable(beads);
    final savedBeads = (await repository.getConsumableById(beadsId))!;
    await repository.recordStockIn(
      consumable: savedBeads,
      quantity: 199,
      activityType: InventoryActivity.openingStock,
    );

    final thread = item(
      category: Consumable.categoryAariThread,
      name: 'Aari red',
      trackingType: Consumable.trackingPercentage,
      unit: Consumable.unitMetres,
      reorder: 10,
      pack: 500,
    );
    await repository.insertConsumable(thread);

    expect((await repository.getLowStockConsumables()).map((item) => item.name),
        contains('Silver beads'));
    expect((await repository.getLowStockConsumables()).map((item) => item.name),
        isNot(contains('Aari red')));
    await db.close();
  });

  test('rejects invalid quantities and prevents increasing thread percentage', () async {
    final db = await openTestDb();
    final repository = ConsumableRepository(database: db);
    final model = item(
      category: Consumable.categoryEmbroideryThread,
      name: 'White thread',
      trackingType: Consumable.trackingPercentage,
      unit: Consumable.unitMetres,
      pack: 1000,
    );
    final id = await repository.insertConsumable(model);
    final saved = (await repository.getConsumableById(id))!;
    final spoolId = await repository.addThreadSpool(
      consumable: saved,
      approximateLengthM: 1000,
    );
    final spool = (await repository.getSpools(id)).single;

    await expectLater(
      repository.updateSpoolRemaining(spool: spool, remainingPercent: 101),
      throwsArgumentError,
    );
    await expectLater(
      repository.recordStockIn(
        consumable: saved,
        quantity: -5,
        activityType: InventoryActivity.purchase,
      ),
      throwsArgumentError,
    );
    expect((await repository.getSpools(id)).single.id, spoolId);
    await db.close();
  });
}
