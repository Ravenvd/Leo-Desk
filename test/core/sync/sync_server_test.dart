import 'package:flutter_test/flutter_test.dart';
import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/core/sync/sync_client.dart';
import 'package:leo_desk/core/sync/sync_config.dart';
import 'package:leo_desk/core/sync/sync_server.dart';
import 'package:leo_desk/features/billing/repositories/bill_repository.dart';
import 'package:leo_desk/features/inventory/models/asset.dart';
import 'package:leo_desk/features/inventory/models/consumable.dart';
import 'package:leo_desk/features/inventory/repositories/asset_repository.dart';
import 'package:leo_desk/features/inventory/repositories/consumable_repository.dart';
import 'package:leo_desk/features/inventory/repositories/maintenance_repository.dart';
import 'package:leo_desk/features/inventory/repositories/maintenance_repository.dart';
import 'package:leo_desk/features/customers/models/customer.dart';
import 'package:leo_desk/features/customers/repositories/customer_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database database;
  late SyncServer server;

  Customer makeCustomer({
    required String uuid,
    required String name,
    String syncStatus = 'synced',
  }) {
    final now = DateTime.utc(2026, 1, 1);
    return Customer(
      uuid: uuid,
      syncStatus: syncStatus,
      name: name,
      phone: '9876543210',
      whatsapp: '9876543210',
      email: 'test@example.com',
      address: 'Test address',
      notes: 'Test notes',
      createdAt: now,
      updatedAt: now,
    );
  }

  setUp(() async {
    database = await AppDatabase.openTestDatabase();
    server = SyncServer(
      customerRepository: CustomerRepository(database: database),
      billRepository: BillRepository(database: database),
      assetRepository: AssetRepository(database: database),
      maintenanceRepository: MaintenanceRepository(database: database),
      consumableRepository: ConsumableRepository(database: database),
      maintenanceRepository: MaintenanceRepository(database: database),
    );
    await server.start(port: 0);
  });

  tearDown(() async {
    await server.stop();
    await database.close();
  });

  test('client keeps customer pending when server rejects a pending conflict', () async {
    final repository = CustomerRepository(database: database);
    final local = makeCustomer(
      uuid: 'customer-network-conflict',
      name: 'Windows Version',
      syncStatus: 'pending',
    );
    await database.insert('customers', local.toMap()..remove('id'));

    final client = SyncClient(
      serverAddress: '127.0.0.1',
      port: server.port!,
      token: SyncConfig.defaultToken,
    );
    final incoming = makeCustomer(
      uuid: 'customer-network-conflict',
      name: 'Android Version',
      syncStatus: 'pending',
    );

    final sent = await client.sendCustomer(incoming);

    expect(sent, isFalse);

    final customers = await repository.getAll();
    expect(customers, hasLength(1));
    expect(customers.single.name, 'Windows Version');
    expect(customers.single.syncStatus, 'pending');
  });
  test('syncs assets through the Windows host by UUID', () async {
    final client = SyncClient(serverAddress: '127.0.0.1', port: server.port!, token: SyncConfig.defaultToken);
    final now = DateTime.utc(2026, 10, 30);
    final asset = Asset(uuid: 'asset-sync-test', assetCode: 'AST-SYNC-TEST', name: 'Embroidery machine', createdAt: now, updatedAt: now);
    expect(await client.sendAsset(asset), isTrue);
    final fetched = await client.fetchAssets();
    expect(fetched.single.uuid, asset.uuid);
    expect(fetched.single.name, 'Embroidery machine');
  });

  test('syncs consumable records without transmitting local integer IDs', () async {
    final client = SyncClient(serverAddress: '127.0.0.1', port: server.port!, token: SyncConfig.defaultToken);
    final now = DateTime.utc(2026, 10, 30);
    final consumable = Consumable(uuid: 'consumable-sync-test', category: Consumable.categoryBeads, name: 'Gold beads', trackingType: Consumable.trackingQuantity, stockUnit: Consumable.unitGrams, createdAt: now, updatedAt: now);
    final payload = consumable.toMap()..remove('id')..remove('sync_status');
    payload['record_type'] = 'consumables';
    expect(await client.sendInventoryRecord(payload), isTrue);
    final fetched = await client.fetchInventoryRecords();
    expect(fetched.single['uuid'], consumable.uuid);
    expect(fetched.single.containsKey('id'), isFalse);
    expect(fetched.single['record_type'], 'consumables');
  });
  test('Windows allocates canonical asset codes for offline-created assets', () async {
    final repository = AssetRepository(database: database);
    final now = DateTime.utc(2026, 10, 30);
    await repository.insert(Asset(uuid: 'asset-windows-existing', name: 'Existing machine', createdAt: now, updatedAt: now));
    final client = SyncClient(serverAddress: '127.0.0.1', port: server.port!, token: SyncConfig.defaultToken);
    final offlineAsset = Asset(uuid: 'asset-android-new', assetCode: 'AST-0001', name: 'Offline machine', createdAt: now, updatedAt: now);
    expect(await client.sendAsset(offlineAsset), isTrue);
    final fetched = await client.fetchAssets();
    expect(fetched.singleWhere((asset) => asset.uuid == offlineAsset.uuid).assetCode, 'AST-0002');
  });
  test('syncs maintenance records through the asset UUID relationship', () async {
    final client = SyncClient(serverAddress: '127.0.0.1', port: server.port!, token: SyncConfig.defaultToken);
    final now = DateTime.utc(2026, 10, 30);
    final asset = Asset(uuid: 'maintenance-parent-asset', name: 'Machine', createdAt: now, updatedAt: now);
    expect(await client.sendAsset(asset), isTrue);
    final maintenance = <String, Object?>{
      'uuid': 'maintenance-sync-test',
      'sync_status': 'pending',
      'asset_uuid': asset.uuid,
      'maintenance_date': now.toIso8601String(),
      'description': 'Annual servicing',
      'cost_paise': 150000,
      'notes': 'Sync test',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    expect(await client.sendMaintenanceRecord(maintenance), isTrue);
    final fetched = await client.fetchMaintenanceRecords();
    expect(fetched.single['uuid'], 'maintenance-sync-test');
    expect(fetched.single['asset_uuid'], asset.uuid);
    expect(fetched.single.containsKey('asset_id'), isFalse);
  });
}
