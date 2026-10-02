import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:leo_desk/core/database/database_schema.dart';
import 'package:leo_desk/features/inventory/models/asset.dart';
import 'package:leo_desk/features/inventory/repositories/asset_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('v13 migration creates the assets table', () async {
    final database = await openDatabase(
      inMemoryDatabasePath,
      version: 12,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE customers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid TEXT NOT NULL UNIQUE,
            sync_status TEXT NOT NULL DEFAULT 'synced',
            name TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );

    await database.close();

    final migrated = await openDatabase(
      inMemoryDatabasePath,
      version: 13,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 13) {
          await DatabaseSchema.upgradeToVersion13(db);
        }
      },
    );

    final tables = await migrated.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'assets'",
    );

    expect(tables, hasLength(1));

    final columns = await migrated.rawQuery('PRAGMA table_info(assets)');
    final columnNames = columns.map((column) => column['name']).toList();

    expect(
      columnNames,
      containsAll([
        'id',
        'uuid',
        'sync_status',
        'asset_code',
        'name',
        'purchase_date',
        'purchase_cost_paise',
        'manufacturer_model',
        'serial_number',
        'warranty_information',
        'status',
        'notes',
        'created_at',
        'updated_at',
      ]),
    );

    await migrated.close();
  });

  test('asset repository generates sequential asset codes', () async {
    final database = await openDatabase(
      inMemoryDatabasePath,
      version: DatabaseSchema.version,
      onCreate: (db, version) async {
        for (final statement in DatabaseSchema.createStatements) {
          await db.execute(statement);
        }
      },
    );

    final repository = AssetRepository(database: database);
    final now = DateTime(2026, 10, 2);

    final firstId = await repository.insert(
      Asset(
        assetCode: 'unused',
        name: 'Embroidery Machine',
        purchaseDate: now,
        purchaseCostPaise: 70000000,
        status: Asset.statusActive,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final secondId = await repository.insert(
      Asset(
        assetCode: 'unused',
        name: 'Thread Cutter',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final first = await repository.getById(firstId);
    final second = await repository.getById(secondId);

    expect(first?.assetCode, 'AST-0001');
    expect(second?.assetCode, 'AST-0002');
    expect(first?.name, 'Embroidery Machine');
    expect(first?.purchaseCostPaise, 70000000);
    expect(second?.status, Asset.statusActive);

    await database.close();
  });
}
