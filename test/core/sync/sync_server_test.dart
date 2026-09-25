import 'package:flutter_test/flutter_test.dart';
import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/core/sync/sync_client.dart';
import 'package:leo_desk/core/sync/sync_config.dart';
import 'package:leo_desk/core/sync/sync_server.dart';
import 'package:leo_desk/features/billing/repositories/bill_repository.dart';
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
}
