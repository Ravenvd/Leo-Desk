import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:leo_desk/core/database/database_schema.dart';
import 'package:leo_desk/features/inventory/models/asset.dart';
import 'package:leo_desk/features/inventory/repositories/asset_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<Database> createCurrentDatabase() {
    return openDatabase(
      inMemoryDatabasePath,
      version: DatabaseSchema.version,
      onCreate: (db, version) async {
        for (final statement in DatabaseSchema.createStatements) {
          await db.execute(statement);
        }
      },
    );
  }

  Future<String> createV12DatabasePath() async {
    final path = '${Directory.systemTemp.path}/leo_desk_asset_v12_${DateTime.now().microsecondsSinceEpoch}.db';
    final database = await openDatabase(
      path,
      version: 12,
      onCreate: (db, version) async {
        // DatabaseSchema.createStatements represents the current v13 schema.
        // The first statement is the v13-only assets table, so the remaining
        // statements reproduce the actual v12 schema.
        for (final statement in DatabaseSchema.createStatements.skip(1)) {
          await db.execute(statement);
        }
      },
    );
    await database.close();
    return path;
  }

  Asset makeAsset({
    String name = 'Embroidery Machine',
    String? assetCode,
    String status = Asset.statusActive,
  }) {
    final now = DateTime(2026, 10, 2, 10, 0);
    return Asset(
      assetCode: assetCode,
      name: name,
      purchaseDate: DateTime(2026, 7, 12),
      purchaseCostPaise: 70000000,
      manufacturerModel: 'Example Model',
      serialNumber: 'SN-001',
      warrantyInformation: 'Valid until 2027-07-11',
      status: status,
      notes: 'Test asset',
      createdAt: now,
      updatedAt: now,
    );
  }

  test('v12 to v13 migration preserves existing data and adds assets', () async {
    final path = await createV12DatabasePath();
    try {
      final database = await openDatabase(path, version: 12);

    final customerId = await database.insert('customers', {
      'uuid': 'customer-v12',
      'sync_status': 'synced',
      'name': 'Migration Customer',
      'created_at': '2026-10-01T10:00:00.000',
      'updated_at': '2026-10-01T10:00:00.000',
    });

    final orderId = await database.insert('orders', {
      'uuid': 'order-v12',
      'sync_status': 'synced',
      'order_number': 'ORD-V12-001',
      'customer_id': customerId,
      'order_date': '2026-10-01T10:00:00.000',
      'expected_delivery_date': '2026-10-05T10:00:00.000',
      'stitching_required': 0,
      'stitching_price_paise': 0,
      'status': 'New',
      'notes': 'Migration test',
      'created_at': '2026-10-01T10:00:00.000',
      'updated_at': '2026-10-01T10:00:00.000',
    });

    await database.insert('invoices', {
      'uuid': 'invoice-v12',
      'sync_status': 'synced',
      'order_id': orderId,
      'order_uuid': 'order-v12',
      'customer_id': customerId,
      'customer_uuid': 'customer-v12',
      'invoice_number': 'INV-V12-001',
      'invoice_date': '2026-10-01T10:00:00.000',
      'subtotal_paise': 10000,
      'total_paise': 10000,
      'notes': 'Migration invoice',
      'created_at': '2026-10-01T10:00:00.000',
      'updated_at': '2026-10-01T10:00:00.000',
    });

    await database.insert('bills', {
      'uuid': 'bill-v12',
      'sync_status': 'synced',
      'customer_id': customerId,
      'customer_uuid': 'customer-v12',
      'order_id': orderId,
      'order_uuid': 'order-v12',
      'bill_number': 'BILL-V12-001',
      'bill_date': '2026-10-01T10:00:00.000',
      'subtotal_paise': 10000,
      'total_paise': 10000,
      'amount_paid_paise': 5000,
      'notes': 'Migration bill',
      'created_at': '2026-10-01T10:00:00.000',
      'updated_at': '2026-10-01T10:00:00.000',
    });

      await database.close();

      final migrated = await openDatabase(
        path,
      version: DatabaseSchema.version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 13) {
          await DatabaseSchema.upgradeToVersion13(db);
        }
      },
    );

    expect(await migrated.getVersion(), 13);

    final tables = await migrated.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'assets'",
    );
    expect(tables, hasLength(1));

    final customer = await migrated.query(
      'customers',
      where: 'uuid = ?',
      whereArgs: ['customer-v12'],
    );
    expect(customer, hasLength(1));
    expect(customer.single['name'], 'Migration Customer');

    final order = await migrated.query(
      'orders',
      where: 'uuid = ?',
      whereArgs: ['order-v12'],
    );
    expect(order, hasLength(1));
    expect(order.single['customer_id'], customerId);

    final invoice = await migrated.query(
      'invoices',
      where: 'uuid = ?',
      whereArgs: ['invoice-v12'],
    );
    expect(invoice, hasLength(1));
    expect(invoice.single['order_id'], orderId);

    final bill = await migrated.query(
      'bills',
      where: 'uuid = ?',
      whereArgs: ['bill-v12'],
    );
    expect(bill, hasLength(1));
    expect(bill.single['order_id'], orderId);

      await migrated.close();
    } finally {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  });

  test('v13 assets table has the expected schema', () async {
    final database = await createCurrentDatabase();

    final columns = await database.rawQuery('PRAGMA table_info(assets)');
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

    await database.close();
  });

  test('creating an asset generates uuid and automatic asset code', () async {
    final database = await createCurrentDatabase();
    final repository = AssetRepository(database: database);

    final id = await repository.insert(
      Asset(
        name: 'Embroidery Machine',
        createdAt: DateTime(2026, 10, 2),
        updatedAt: DateTime(2026, 10, 2),
      ),
    );

    final asset = await repository.getById(id);

    expect(asset, isNotNull);
    expect(asset!.uuid, isNotEmpty);
    expect(asset.assetCode, 'AST-0001');
    expect(asset.status, Asset.statusActive);
    expect(asset.syncStatus, Asset.syncStatusPending);

    await database.close();
  });

  test('asset codes increment and are not reused after deletion', () async {
    final database = await createCurrentDatabase();
    final repository = AssetRepository(database: database);

    final firstId = await repository.insert(makeAsset(name: 'Machine 1'));
    final secondId = await repository.insert(makeAsset(name: 'Machine 2'));

    expect((await repository.getById(firstId))!.assetCode, 'AST-0001');
    expect((await repository.getById(secondId))!.assetCode, 'AST-0002');

    await repository.finalizeDeletion(
      (await repository.getById(firstId))!.uuid,
    );

    final thirdId = await repository.insert(makeAsset(name: 'Machine 3'));
    expect((await repository.getById(thirdId))!.assetCode, 'AST-0003');

    await database.close();
  });

  test('asset repository reads and updates all asset fields', () async {
    final database = await createCurrentDatabase();
    final repository = AssetRepository(database: database);

    final id = await repository.insert(makeAsset());
    final original = await repository.getById(id);

    expect(original!.name, 'Embroidery Machine');
    expect(original.purchaseDate, DateTime(2026, 7, 12));
    expect(original.purchaseCostPaise, 70000000);
    expect(original.manufacturerModel, 'Example Model');
    expect(original.serialNumber, 'SN-001');
    expect(original.warrantyInformation, 'Valid until 2027-07-11');
    expect(original.status, Asset.statusActive);
    expect(original.notes, 'Test asset');

    final updated = original.copyWith(
      name: 'Main Embroidery Machine',
      status: Asset.statusMaintenance,
      notes: 'Sent for servicing',
      manufacturerModel: 'Updated Model',
    );

    await repository.update(updated);

    final reloaded = await repository.getById(id);
    expect(reloaded!.assetCode, original.assetCode);
    expect(reloaded.uuid, original.uuid);
    expect(reloaded.name, 'Main Embroidery Machine');
    expect(reloaded.status, Asset.statusMaintenance);
    expect(reloaded.notes, 'Sent for servicing');
    expect(reloaded.manufacturerModel, 'Updated Model');
    expect(reloaded.syncStatus, Asset.syncStatusPending);

    await database.close();
  });

  test('asset repository supports lookup by uuid and listing', () async {
    final database = await createCurrentDatabase();
    final repository = AssetRepository(database: database);

    final firstId = await repository.insert(makeAsset(name: 'Z Machine'));
    final secondId = await repository.insert(makeAsset(name: 'A Machine'));

    final first = await repository.getById(firstId);
    expect(await repository.getByUuid(first!.uuid), isNotNull);

    final assets = await repository.getAll();
    expect(assets.map((asset) => asset.name).toList(), [
      'A Machine',
      'Z Machine',
    ]);

    await database.close();
  });

  test('deletion is soft until sync acknowledgement', () async {
    final database = await createCurrentDatabase();
    final repository = AssetRepository(database: database);

    final id = await repository.insert(makeAsset());
    final asset = await repository.getById(id);

    await repository.delete(id);

    expect(await repository.getAll(), isEmpty);

    final pending = await repository.getPending();
    expect(pending, hasLength(1));
    expect(pending.single.syncStatus, Asset.syncStatusDeletedPending);

    await repository.acknowledgeSyncedOrDeleted(asset!.uuid);

    expect(await repository.getById(id), isNull);

    await database.close();
  });

  test('asset status constants cover the planned lifecycle', () {
    expect(
      Asset.statuses,
      containsAll([
        Asset.statusActive,
        Asset.statusMaintenance,
        Asset.statusInactive,
        Asset.statusCondemned,
      ]),
    );
  });
}
