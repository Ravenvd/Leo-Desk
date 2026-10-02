import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:leo_desk/core/database/database_schema.dart';
import 'package:leo_desk/features/inventory/models/asset.dart';
import 'package:leo_desk/features/inventory/models/maintenance_record.dart';
import 'package:leo_desk/features/inventory/repositories/asset_repository.dart';
import 'package:leo_desk/features/inventory/repositories/maintenance_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<Database> database() => openDatabase(
        inMemoryDatabasePath,
        version: DatabaseSchema.version,
        onCreate: (db, version) async {
          for (final statement in DatabaseSchema.createStatements) {
            await db.execute(statement);
          }
        },
      );

  test('v13 to v14 migration creates maintenance table', () async {
    final path =
        '${Directory.systemTemp.path}/leo_desk_maintenance_v13_${DateTime.now().microsecondsSinceEpoch}.db';
    final old = await openDatabase(
      path,
      version: 13,
      onCreate: (db, version) async {
        for (final statement in DatabaseSchema.createStatements) {
          if (!statement.contains('maintenance_records')) {
            await db.execute(statement);
          }
        }
      },
    );
    await old.close();

    try {
      final db = await openDatabase(
        path,
        version: DatabaseSchema.version,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 14) {
            await DatabaseSchema.upgradeToVersion14(db);
          }
        },
      );
      final columns = await db.rawQuery('PRAGMA table_info(maintenance_records)');
      expect(columns.map((e) => e['name']), containsAll([
        'id', 'uuid', 'sync_status', 'asset_id', 'asset_uuid',
        'maintenance_date', 'description', 'cost_paise', 'notes',
        'created_at', 'updated_at',
      ]));
      await db.close();
    } finally {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  });

  test('maintenance records can be created, read, updated and deleted', () async {
    final db = await database();
    final assets = AssetRepository(database: db);
    final maintenance = MaintenanceRepository(database: db);

    final assetId = await assets.insert(
      Asset(name: 'Machine', createdAt: DateTime(2026, 10, 2), updatedAt: DateTime(2026, 10, 2)),
    );
    final asset = await assets.getById(assetId);
    final record = MaintenanceRecord(
      assetId: assetId,
      assetUuid: asset!.uuid,
      maintenanceDate: DateTime(2026, 10, 1),
      description: 'Routine servicing',
      costPaise: 485000,
      notes: 'Cleaned and lubricated',
      createdAt: DateTime(2026, 10, 2),
      updatedAt: DateTime(2026, 10, 2),
    );

    final id = await maintenance.insert(record);
    final saved = await maintenance.getById(id);
    expect(saved!.uuid, isNotEmpty);
    expect(saved.description, 'Routine servicing');
    expect(saved.costPaise, 485000);
    expect(saved.syncStatus, MaintenanceRecord.syncStatusPending);

    await maintenance.update(saved.copyWith(
      description: 'Full servicing',
      costPaise: 500000,
      notes: 'Completed',
    ));
    final updated = await maintenance.getById(id);
    expect(updated!.description, 'Full servicing');
    expect(updated.costPaise, 500000);

    expect((await maintenance.getForAsset(assetId)), hasLength(1));
    await maintenance.delete(id);
    expect(await maintenance.getForAsset(assetId), isEmpty);
    expect(await maintenance.getPending(), hasLength(1));

    await db.close();
  });

  test('maintenance records are removed when their asset is deleted', () async {
    final db = await database();
    final assets = AssetRepository(database: db);
    final maintenance = MaintenanceRepository(database: db);

    final assetId = await assets.insert(
      Asset(name: 'Machine', createdAt: DateTime(2026, 10, 2), updatedAt: DateTime(2026, 10, 2)),
    );
    final asset = await assets.getById(assetId);
    await maintenance.insert(MaintenanceRecord(
      assetId: assetId,
      assetUuid: asset!.uuid,
      maintenanceDate: DateTime(2026, 10, 2),
      description: 'Repair',
      createdAt: DateTime(2026, 10, 2),
      updatedAt: DateTime(2026, 10, 2),
    ));

    await assets.finalizeDeletion(asset.uuid);
    expect(await maintenance.getForAsset(assetId), isEmpty);
    await db.close();
  });
}
