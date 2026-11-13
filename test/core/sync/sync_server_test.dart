import 'package:flutter_test/flutter_test.dart';
import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/core/sync/sync_client.dart';
import 'package:leo_desk/core/sync/sync_config.dart';
import 'package:leo_desk/core/sync/sync_server.dart';
import 'package:leo_desk/features/billing/repositories/bill_repository.dart';
import 'package:leo_desk/features/expenses/repositories/expense_repository.dart';
import 'package:leo_desk/features/inventory/models/asset.dart';
import 'package:leo_desk/features/inventory/models/consumable.dart';
import 'package:leo_desk/features/inventory/repositories/asset_repository.dart';
import 'package:leo_desk/features/inventory/repositories/consumable_repository.dart';
import 'package:leo_desk/features/inventory/repositories/maintenance_repository.dart';
import 'package:leo_desk/features/staff/models/staff.dart';
import 'package:leo_desk/features/staff/repositories/staff_repository.dart';
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
      expenseRepository: ExpenseRepository(database: database),
      assetRepository: AssetRepository(database: database),
      consumableRepository: ConsumableRepository(database: database),
      maintenanceRepository: MaintenanceRepository(database: database),
      staffRepository: StaffRepository(database: database),
    );
    await server.start(port: 0);
  });

  tearDown(() async {
    await server.stop();
    await database.close();
  });

  test('Windows customer record remains canonical over Android edits', () async {
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

    final canonical = await client.sendCustomerCanonical(incoming);

    expect(canonical, isNotNull);
    expect(canonical!['uuid'], incoming.uuid);
    expect(canonical['name'], 'Windows Version');

    final customers = await repository.getAll();
    expect(customers, hasLength(1));
    expect(customers.single.name, 'Windows Version');
    expect(customers.single.syncStatus, 'pending');
    expect(customers.single.name, 'Windows Version');
  });
  test('staff push returns the complete canonical Windows profile', () async {
    final now = DateTime.utc(2026, 11, 1);
    final windowsStaff = <String, Object?>{
      'uuid': 'staff-server-canonical',
      'sync_status': 'pending',
      'name': 'Windows Staff',
      'phone': '1111111111',
      'role': 'Supervisor',
      'joined_on': '2026-01-01',
      'is_active': 1,
      'notes': 'Windows notes',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    await database.insert('staff', windowsStaff);

    final client = SyncClient(
      serverAddress: '127.0.0.1',
      port: server.port!,
      token: SyncConfig.defaultToken,
    );
    final canonical = await client.sendStaffProfileCanonical({
      ...windowsStaff,
      'name': 'Android Edit',
      'role': 'Operator',
      'notes': 'Android notes',
    });

    expect(canonical, isNotNull);
    expect(canonical!['uuid'], windowsStaff['uuid']);
    expect(canonical['name'], 'Windows Staff');
    expect(canonical['role'], 'Supervisor');
    expect(canonical['notes'], 'Windows notes');
  });

  test('syncs assets through the Windows host by UUID', () async {
    final client = SyncClient(serverAddress: '127.0.0.1', port: server.port!, token: SyncConfig.defaultToken);
    final now = DateTime.utc(2026, 10, 30);
    final asset = Asset(uuid: 'asset-sync-test', assetCode: 'AST-SYNC-TEST', name: 'Embroidery machine', createdAt: now, updatedAt: now);
    final canonical = await client.sendAsset(asset);
    expect(canonical, isNotNull);
    expect(canonical!['uuid'], asset.uuid);
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
    final canonical = await client.sendAsset(offlineAsset);
    expect(canonical, isNotNull);
    expect(canonical!['asset_code'], 'AST-0001A');
    final fetched = await client.fetchAssets();
    expect(fetched.singleWhere((asset) => asset.uuid == offlineAsset.uuid).assetCode, 'AST-0001A');
    final deleted = offlineAsset.copyWith(syncStatus: Asset.syncStatusDeletedPending);
    expect(await client.sendAssetDeletion(deleted.uuid), isTrue);
    final tombstone = (await client.fetchAssets()).singleWhere((asset) => asset.uuid == offlineAsset.uuid);
    expect(tombstone.syncStatus, Asset.syncStatusDeletedPending);
  });
  test('syncs maintenance records through the asset UUID relationship', () async {
    final client = SyncClient(serverAddress: '127.0.0.1', port: server.port!, token: SyncConfig.defaultToken);
    final now = DateTime.utc(2026, 10, 30);
    final asset = Asset(uuid: 'maintenance-parent-asset', name: 'Machine', createdAt: now, updatedAt: now);
    expect(await client.sendAsset(asset), isNotNull);
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
    maintenance['sync_status'] = 'deleted_pending';
    expect(await client.sendMaintenanceRecord(maintenance), isTrue);
    final tombstones = await client.fetchMaintenanceRecords();
    expect(tombstones.single['sync_status'], 'deleted_pending');
  });

  test('staff attendance POST returns the Windows natural-key canonical row', () async {
    final staffRepository = StaffRepository(database: database);
    final now = DateTime.utc(2026, 11, 5);
    final staff = StaffMember(
      uuid: 'staff-http-attendance',
      name: 'Attendance Staff',
      joinedOn: now,
      createdAt: now,
      updatedAt: now,
    );
    final staffId = await staffRepository.insertStaff(staff);
    final windowsAttendance = StaffAttendance(
      uuid: 'attendance-http-windows',
      staffId: staffId,
      staffUuid: staff.uuid,
      attendanceDate: now,
      status: StaffAttendance.fullDay,
      notes: 'Windows canonical',
      createdAt: now,
      updatedAt: now,
    );
    await database.insert(
      'staff_attendance',
      windowsAttendance.toMap()..remove('id'),
    );

    final client = SyncClient(
      serverAddress: '127.0.0.1',
      port: server.port!,
      token: SyncConfig.defaultToken,
    );
    final canonical = await client.sendStaffRecordCanonical(
      'staff_attendance',
      {
        ...windowsAttendance.toMap(),
        'uuid': 'attendance-http-android',
        'status': StaffAttendance.absent,
        'notes': 'Android duplicate',
      },
    );

    expect(canonical, isNotNull);
    expect(canonical!['uuid'], windowsAttendance.uuid);
    expect(canonical['status'], StaffAttendance.fullDay);
    expect(canonical['notes'], 'Windows canonical');
    expect((await staffRepository.getAllAttendanceForSync()), hasLength(1));
  });

  test('staff payment POST returns complete canonical Windows payment', () async {
    final staffRepository = StaffRepository(database: database);
    final now = DateTime.utc(2026, 11, 6);
    final staff = StaffMember(
      uuid: 'staff-http-payment',
      name: 'Payroll Staff',
      joinedOn: now,
      createdAt: now,
      updatedAt: now,
    );
    final staffId = await staffRepository.insertStaff(staff);
    final windowsPayment = StaffPayment(
      uuid: 'payment-http-windows',
      staffId: staffId,
      staffUuid: staff.uuid,
      periodStart: DateTime.utc(2026, 11, 1),
      periodEnd: DateTime.utc(2026, 11, 30),
      paymentDate: now,
      amountPaise: 175000,
      notes: 'Windows payroll',
      createdAt: now,
      updatedAt: now,
    );
    await database.insert(
      'staff_payments',
      windowsPayment.toMap()..remove('id'),
    );

    final client = SyncClient(
      serverAddress: '127.0.0.1',
      port: server.port!,
      token: SyncConfig.defaultToken,
    );
    final canonical = await client.sendStaffRecordCanonical(
      'staff_payments',
      {
        ...windowsPayment.toMap(),
        'amount_paise': 1,
        'notes': 'Android edit',
      },
    );

    expect(canonical, isNotNull);
    expect(canonical!['uuid'], windowsPayment.uuid);
    expect(canonical['amount_paise'], 175000);
    expect(canonical['notes'], 'Windows payroll');
    expect((await staffRepository.getAllPaymentsForSync()), hasLength(1));

    final newPayment = {
      ...windowsPayment.toMap(),
      'uuid': 'payment-http-new',
      'amount_paise': 95000,
      'notes': 'New Android payroll',
    };
    final inserted = await client.sendStaffRecordCanonical(
      'staff_payments',
      newPayment,
    );
    expect(inserted, isNotNull);
    expect(inserted!['uuid'], 'payment-http-new');
    expect(inserted['amount_paise'], 95000);
    expect(inserted['staff_id'], staffId);
    expect((await staffRepository.getAllPaymentsForSync()), hasLength(2));
  });
}
