import 'package:flutter_test/flutter_test.dart';
import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/core/sync/sync_client.dart';
import 'package:leo_desk/core/sync/sync_config.dart';
import 'package:leo_desk/core/sync/sync_server.dart';
import 'package:leo_desk/features/billing/repositories/bill_repository.dart';
import 'package:leo_desk/features/customers/repositories/customer_repository.dart';
import 'package:leo_desk/features/expenses/repositories/expense_repository.dart';
import 'package:leo_desk/features/invoices/repositories/invoice_repository.dart';
import 'package:leo_desk/features/inventory/models/asset.dart';
import 'package:leo_desk/features/inventory/repositories/asset_repository.dart';
import 'package:leo_desk/features/inventory/repositories/consumable_repository.dart';
import 'package:leo_desk/features/inventory/repositories/maintenance_repository.dart';
import 'package:leo_desk/features/orders/repositories/order_repository.dart';
import 'package:leo_desk/features/staff/repositories/staff_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database database;
  late AssetRepository assets;
  late SyncServer server;
  late SyncClient client;

  final now = DateTime.utc(2026, 11, 13, 10);

  Asset makeAsset({
    required String uuid,
    required String code,
    String name = 'Embroidery machine',
    String syncStatus = Asset.syncStatusPending,
  }) {
    return Asset(
      uuid: uuid,
      syncStatus: syncStatus,
      assetCode: code,
      name: name,
      manufacturerModel: 'Model X',
      createdAt: now,
      updatedAt: now,
    );
  }

  setUp(() async {
    database = await AppDatabase.openTestDatabase();
    assets = AssetRepository(database: database);
    server = SyncServer(
      customerRepository: CustomerRepository(database: database),
      billRepository: BillRepository(database: database),
      expenseRepository: ExpenseRepository(database: database),
      invoiceRepository: InvoiceRepository(database: database),
      orderRepository: OrderRepository(database: database),
      assetRepository: assets,
      consumableRepository: ConsumableRepository(database: database),
      maintenanceRepository: MaintenanceRepository(database: database),
      staffRepository: StaffRepository(database: database),
    );
    await server.start(port: 0);
    client = SyncClient(
      serverAddress: '127.0.0.1',
      port: server.port!,
      token: SyncConfig.defaultToken,
    );
  });

  tearDown(() async {
    await server.stop();
    await database.close();
  });

  test('same UUID returns the complete Windows asset unchanged', () async {
    final windowsAsset = makeAsset(
      uuid: 'windows-canonical-asset',
      code: 'AST-0007',
      name: 'Windows machine',
      syncStatus: Asset.syncStatusPending,
    );
    await assets.insert(windowsAsset);

    final response = await client.sendAsset(
      makeAsset(
        uuid: windowsAsset.uuid,
        code: 'AST-9999',
        name: 'Android attempted edit',
      ),
    );

    expect(response, isNotNull);
    expect(response!['asset_code'], 'AST-0007');
    expect(response['name'], 'Windows machine');

    final persisted = await assets.getByUuid(windowsAsset.uuid);
    expect(persisted, isNotNull);
    expect(persisted!.assetCode, 'AST-0007');
    expect(persisted.name, 'Windows machine');
    expect(persisted.syncStatus, Asset.syncStatusPending);
  });

  test('distinct UUID collisions receive stable A and B suffixes', () async {
    await assets.insert(makeAsset(
      uuid: 'windows-asset-base',
      code: 'AST-0001',
      syncStatus: Asset.syncStatusSynced,
    ));

    final first = makeAsset(uuid: 'android-asset-a', code: 'AST-0001');
    final responseA = await client.sendAsset(first);
    expect(responseA, isNotNull);
    expect(responseA!['asset_code'], 'AST-0001A');

    final retryA = await client.sendAsset(first);
    expect(retryA, isNotNull);
    expect(retryA!['asset_code'], 'AST-0001A');

    final responseB = await client.sendAsset(
      makeAsset(uuid: 'android-asset-b', code: 'AST-0001'),
    );
    expect(responseB, isNotNull);
    expect(responseB!['asset_code'], 'AST-0001B');

    final saved = await assets.getAllForSync();
    expect(saved, hasLength(3));
    expect(
      saved.map((asset) => asset.assetCode).toSet(),
      {'AST-0001', 'AST-0001A', 'AST-0001B'},
    );
  });

  test('concurrent asset collisions receive different canonical suffixes',
      () async {
    await assets.insert(makeAsset(
      uuid: 'windows-concurrent-asset',
      code: 'AST-0009',
      syncStatus: Asset.syncStatusSynced,
    ));

    final responses = await Future.wait([
      client.sendAsset(makeAsset(
        uuid: 'android-concurrent-asset-a',
        code: 'AST-0009',
      )),
      client.sendAsset(makeAsset(
        uuid: 'android-concurrent-asset-b',
        code: 'AST-0009',
      )),
    ]);

    expect(responses.every((response) => response != null), isTrue);
    final codes = responses
        .map((response) => response!['asset_code'] as String)
        .toSet();
    expect(codes, {'AST-0009A', 'AST-0009B'});

    final saved = await assets.getAllForSync();
    expect(saved, hasLength(3));
    expect(saved.map((asset) => asset.assetCode).toSet(), {
      'AST-0009',
      'AST-0009A',
      'AST-0009B',
    });
  });
}
