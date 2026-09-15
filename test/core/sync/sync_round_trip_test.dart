import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/core/sync/sync_client.dart';
import 'package:leo_desk/core/sync/sync_manager.dart';
import 'package:leo_desk/core/sync/sync_server.dart';
import 'package:leo_desk/features/billing/models/bill.dart';
import 'package:leo_desk/features/billing/models/bill_item.dart';
import 'package:leo_desk/features/billing/repositories/bill_repository.dart';
import 'package:leo_desk/features/customers/models/customer.dart';
import 'package:leo_desk/features/customers/repositories/customer_repository.dart';

Customer makeCustomer(String name) {
  final now = DateTime.now();
  return Customer(
    name: name,
    createdAt: now,
    updatedAt: now,
    customerType: 'personal',
    serviceRequired: 'embroidery',
  );
}

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  // TestWidgetsFlutterBinding replaces HttpClient with a mock that
  // blocks all requests; restore real networking for the round-trip
  // tests against a real SyncServer on loopback.
  HttpOverrides.global = _RealHttpOverrides();

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database serverDb;
  late Database clientDb;
  late CustomerRepository serverCustomers;
  late BillRepository serverBills;
  late CustomerRepository clientCustomers;
  late BillRepository clientBills;
  late SyncServer server;
  late SyncManager manager;
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('leo_sync_test');
    serverDb = await AppDatabase.openTestDatabase(
      path: '${tempDir.path}/server.db',
    );
    clientDb = await AppDatabase.openTestDatabase(
      path: '${tempDir.path}/client.db',
    );

    serverCustomers = CustomerRepository(database: serverDb);
    serverBills = BillRepository(database: serverDb);
    clientCustomers = CustomerRepository(database: clientDb);
    clientBills = BillRepository(database: clientDb);

    server = SyncServer(
      customerRepository: serverCustomers,
      billRepository: serverBills,
    );
    await server.start(port: 0);

    manager = SyncManager(
      client: SyncClient(serverAddress: '127.0.0.1', port: server.port!),
      customerRepository: clientCustomers,
      billRepository: clientBills,
    );
  });

  tearDown(() async {
    await server.stop();
    await serverDb.close();
    await clientDb.close();
    tempDir.deleteSync(recursive: true);
  });

  test('pushes pending customers and bills, then marks them synced', () async {
    final now = DateTime.now();

    final customerId = await clientCustomers.insert(
      makeCustomer('Client Customer'),
    );

    await clientBills.insert(
      bill: Bill(
        customerId: customerId,
        billNumber: 'INV-100',
        billDate: now,
        subtotalPaise: 5000,
        totalPaise: 5000,
        amountPaidPaise: 5000,
        createdAt: now,
        updatedAt: now,
      ),
      items: [
        BillItem(
          billId: 0,
          description: 'Cap embroidery',
          quantity: 1,
          ratePaise: 5000,
          amountPaise: 5000,
        ),
      ],
    );

    final result = await manager.sync();

    expect(result.connected, isTrue);
    expect(result.customersPushed, 1);
    expect(result.billsPushed, 1);

    // Marked synced on the client.
    final localCustomer = await clientCustomers.getById(customerId);
    expect(localCustomer!.syncStatus, 'synced');
    final localBills = await clientBills.getAll();
    expect(localBills.single.syncStatus, 'synced');

    // Present on the server, linked to the server-side customer.
    final remoteCustomers = await serverCustomers.getAll();
    expect(remoteCustomers.single.name, 'Client Customer');
    expect(remoteCustomers.single.syncStatus, 'synced');

    final remoteBills = await serverBills.getAll();
    expect(remoteBills.single.billNumber, 'INV-100');
    expect(remoteBills.single.customerId, remoteCustomers.single.id);
    expect(remoteBills.single.customerUuid, remoteCustomers.single.uuid);

    final remoteItems = await serverBills.getItems(remoteBills.single.id!);
    expect(remoteItems.single.description, 'Cap embroidery');
  });

  test('pulls customers created on the server', () async {
    await serverCustomers.insert(makeCustomer('Server Customer'));

    final result = await manager.sync();

    expect(result.connected, isTrue);
    expect(result.customersPulled, 1);

    final pulled = (await clientCustomers.getAll()).single;
    expect(pulled.name, 'Server Customer');
    expect(pulled.syncStatus, 'synced');
  });

  test(
    'pullAndReplace discards local data and applies the server dataset',
    () async {
      final now = DateTime.now();

      // Server has two customers and a bill.
      final serverCustomerId = await serverCustomers.insert(
        makeCustomer('Server Alice'),
      );
      await serverCustomers.insert(makeCustomer('Server Bob'));
      await serverBills.insert(
        bill: Bill(
          customerId: serverCustomerId,
          billNumber: 'INV-SERVER',
          billDate: now,
          subtotalPaise: 9000,
          totalPaise: 9000,
          amountPaidPaise: 9000,
          createdAt: now,
          updatedAt: now,
        ),
        items: [
          BillItem(
            billId: 0,
            description: 'Server work',
            quantity: 1,
            ratePaise: 9000,
            amountPaise: 9000,
          ),
        ],
      );

      // Client has unsynced junk that must be discarded.
      final junkId = await clientCustomers.insert(makeCustomer('Local Junk'));
      await clientBills.insert(
        bill: Bill(
          customerId: junkId,
          billNumber: 'INV-JUNK',
          billDate: now,
          subtotalPaise: 100,
          totalPaise: 100,
          createdAt: now,
          updatedAt: now,
        ),
        items: [
          BillItem(
            billId: 0,
            description: 'Junk',
            quantity: 1,
            ratePaise: 100,
            amountPaise: 100,
          ),
        ],
      );

      final result = await manager.pullAndReplace();

      expect(result.connected, isTrue);
      expect(result.customersPulled, 2);
      expect(result.billsPulled, 1);

      final customers = await clientCustomers.getAll();
      expect(customers.length, 2);
      expect(
        customers.map((c) => c.name),
        containsAll(['Server Alice', 'Server Bob']),
      );
      expect(customers.every((c) => c.syncStatus == 'synced'), isTrue);

      final bills = await clientBills.getAll();
      expect(bills.single.billNumber, 'INV-SERVER');
      expect(bills.single.syncStatus, 'synced');

      final serverAlice = (await serverCustomers.getAll()).firstWhere(
        (c) => c.name == 'Server Alice',
      );
      final clientAlice = customers.firstWhere((c) => c.name == 'Server Alice');
      expect(bills.single.customerId, clientAlice.id);
      expect(bills.single.customerUuid, serverAlice.uuid);

      final items = await clientBills.getItems(bills.single.id!);
      expect(items.single.description, 'Server work');

      // Nothing left pending after a full replace.
      expect(await clientCustomers.getPending(), isEmpty);
      expect(await clientBills.getPending(), isEmpty);
    },
  );

  test('locally pending record wins over server copy', () async {
    // Same customer (by uuid) exists on both sides.
    final customer = makeCustomer('Original Name');
    await clientCustomers.insert(customer);
    await manager.sync();

    // Client edits locally -> pending again.
    final local = (await clientCustomers.getAll()).single;
    await clientCustomers.update(local.copyWith(name: 'Client Edit'));

    // Server also edits its copy.
    final remote = (await serverCustomers.getAll()).single;
    await serverDb.update(
      'customers',
      {'name': 'Server Edit'},
      where: 'id = ?',
      whereArgs: [remote.id],
    );

    await manager.sync();

    // The client's pending edit was pushed and must survive the pull.
    final after = (await clientCustomers.getAll()).single;
    expect(after.name, 'Client Edit');
    expect(after.syncStatus, 'synced');
  });

  test('reports not connected when the server is down', () async {
    final offlineManager = SyncManager(
      client: SyncClient(
        serverAddress: '127.0.0.1',
        port: 1, // nothing listens here
        timeout: const Duration(seconds: 1),
      ),
      customerRepository: clientCustomers,
      billRepository: clientBills,
    );

    final result = await offlineManager.sync();

    expect(result.connected, isFalse);
    expect(result.totalSynced, 0);
  });

  test('rejects requests without the sync token', () async {
    final badClient = SyncClient(
      serverAddress: '127.0.0.1',
      port: server.port!,
      token: 'wrong-token',
    );

    expect(await badClient.checkConnection(), isFalse);
  });
}
