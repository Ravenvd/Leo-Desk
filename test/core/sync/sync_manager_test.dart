import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/core/sync/sync_client.dart';
import 'package:leo_desk/core/sync/sync_config.dart';
import 'package:leo_desk/core/sync/sync_manager.dart';
import 'package:leo_desk/core/sync/sync_server.dart';
import 'package:leo_desk/features/billing/repositories/bill_repository.dart';
import 'package:leo_desk/features/customers/models/customer.dart';
import 'package:leo_desk/features/customers/repositories/customer_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDirectory;
  late Database serverDatabase;
  late Database clientDatabase;
  late SyncServer server;

  Customer makeCustomer({
    required String uuid,
    required String name,
    String syncStatus = 'pending',
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
      customerType: 'Individual',
      serviceRequired: 'Embroidery',
    );
  }

  setUp(() async {
    testDirectory =
        await Directory.systemTemp.createTemp('leo_desk_sync_test_');

    serverDatabase = await AppDatabase.openTestDatabase(
      path: '${testDirectory.path}${Platform.pathSeparator}server.db',
    );

    clientDatabase = await AppDatabase.openTestDatabase(
      path: '${testDirectory.path}${Platform.pathSeparator}client.db',
    );

    server = SyncServer(
      customerRepository: CustomerRepository(database: serverDatabase),
      billRepository: BillRepository(database: serverDatabase),
    );

    await server.start(port: 0);
  });

  tearDown(() async {
    await server.stop();
    await serverDatabase.close();
    await clientDatabase.close();
    await testDirectory.delete(recursive: true);
  });

  SyncManager makeManager() {
    return SyncManager(
      client: SyncClient(
        serverAddress: '127.0.0.1',
        port: server.port!,
        token: SyncConfig.defaultToken,
      ),
      customerRepository: CustomerRepository(database: clientDatabase),
      billRepository: BillRepository(database: clientDatabase),
      saveLastSyncTime: (_) async {},
    );
  }

  Future<SyncResult> syncWithRealHttpClient() {
    return HttpOverrides.runZoned(
      () => makeManager().sync(),
      createHttpClient: (context) =>
          RealHttpOverrides().createHttpClient(context),
    );
  }

  test('successful customer push marks client customer as synced', () async {
    final clientRepository = CustomerRepository(database: clientDatabase);
    final serverRepository = CustomerRepository(database: serverDatabase);

    final customer = makeCustomer(
      uuid: 'manager-success',
      name: 'New Client Customer',
    );

    await clientRepository.insert(customer);

    final result = await syncWithRealHttpClient();

    expect(result.connected, isTrue);
    expect(result.customersPushed, 1);

    final clientCustomer = await clientRepository.getById(
      (await clientRepository.getAll()).single.id!,
    );

    expect(clientCustomer, isNotNull);
    expect(clientCustomer!.uuid, customer.uuid);
    expect(clientCustomer.syncStatus, 'synced');

    final serverCustomers = await serverRepository.getAll();

    expect(serverCustomers, hasLength(1));
    expect(serverCustomers.single.uuid, customer.uuid);
    expect(serverCustomers.single.name, customer.name);
  });

  test('rejected customer push stays pending after full sync', () async {
    final clientRepository = CustomerRepository(database: clientDatabase);
    final serverRepository = CustomerRepository(database: serverDatabase);

    const uuid = 'manager-conflict';

    final serverCustomer = makeCustomer(
      uuid: uuid,
      name: 'Windows Version',
      syncStatus: 'pending',
    );

    final clientCustomer = makeCustomer(
      uuid: uuid,
      name: 'Android Version',
    );

    await serverRepository.insert(serverCustomer);
    await clientRepository.insert(clientCustomer);

    final result = await syncWithRealHttpClient();

    expect(result.connected, isTrue);
    expect(result.customersPushed, 0);

    final localCustomers = await clientRepository.getAll();

    expect(localCustomers, hasLength(1));
    expect(localCustomers.single.uuid, uuid);
    expect(localCustomers.single.name, 'Android Version');
    expect(localCustomers.single.syncStatus, 'pending');

    final serverCustomers = await serverRepository.getAll();

    expect(serverCustomers, hasLength(1));
    expect(serverCustomers.single.name, 'Windows Version');
    expect(serverCustomers.single.syncStatus, 'pending');
  });
}
