// ignore_for_file: unnecessary_overrides

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/core/sync/sync_client.dart';
import 'package:leo_desk/core/sync/sync_config.dart';
import 'package:leo_desk/core/sync/sync_manager.dart';
import 'package:leo_desk/core/sync/sync_server.dart';
import 'package:leo_desk/features/billing/models/bill.dart';
import 'package:leo_desk/features/billing/models/bill_item.dart';
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

  Bill makeBill({
    required String uuid,
    required int customerId,
    required String customerUuid,
    required String billNumber,
    String syncStatus = 'pending',
    int amountPaidPaise = 0,
    String? notes,
  }) {
    final now = DateTime.utc(2026, 1, 1);

    return Bill(
      uuid: uuid,
      syncStatus: syncStatus,
      customerId: customerId,
      customerUuid: customerUuid,
      billNumber: billNumber,
      billDate: now,
      subtotalPaise: 150000,
      discountPaise: 10000,
      taxPaise: 14000,
      totalPaise: 154000,
      amountPaidPaise: amountPaidPaise,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
  }

  BillItem makeItem({
    required String uuid,
    required String description,
    required double quantity,
    required int ratePaise,
    required int amountPaise,
  }) {
    return BillItem(
      uuid: uuid,
      billId: 0,
      description: description,
      quantity: quantity,
      ratePaise: ratePaise,
      amountPaise: amountPaise,
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

  test('pulls a Windows customer into the Android database', () async {
    final clientRepository = CustomerRepository(database: clientDatabase);
    final serverRepository = CustomerRepository(database: serverDatabase);

    final customer = makeCustomer(
      uuid: 'windows-pull',
      name: 'Windows Customer',
      syncStatus: 'synced',
    );

    await serverRepository.insert(customer);
    await serverRepository.markSynced(customer.uuid);

    final result = await syncWithRealHttpClient();

    expect(result.connected, isTrue);
    expect(result.customersPushed, 0);
    expect(result.customersPulled, 1);

    final localCustomers = await clientRepository.getAll();

    expect(localCustomers, hasLength(1));
    expect(localCustomers.single.uuid, customer.uuid);
    expect(localCustomers.single.name, 'Windows Customer');
    expect(localCustomers.single.syncStatus, 'synced');
  });

  test('Android customer syncs to Windows and later receives Windows changes',
      () async {
    final clientRepository = CustomerRepository(database: clientDatabase);
    final serverRepository = CustomerRepository(database: serverDatabase);

    final customer = makeCustomer(
      uuid: 'android-authority',
      name: 'Android Customer',
    );

    await clientRepository.insert(customer);

    final firstResult = await syncWithRealHttpClient();

    expect(firstResult.connected, isTrue);
    expect(firstResult.customersPushed, 1);

    final serverCustomers = await serverRepository.getAll();
    expect(serverCustomers, hasLength(1));
    expect(serverCustomers.single.name, 'Android Customer');
    expect(serverCustomers.single.syncStatus, 'synced');

    final serverCustomer = serverCustomers.single;
    await serverRepository.update(
      serverCustomer.copyWith(name: 'Windows Authoritative Customer'),
    );

    final secondResult = await syncWithRealHttpClient();

    expect(secondResult.connected, isTrue);
    expect(secondResult.customersPushed, 0);
    expect(secondResult.customersPulled, 1);

    final localCustomers = await clientRepository.getAll();

    expect(localCustomers, hasLength(1));
    expect(localCustomers.single.uuid, customer.uuid);
    expect(localCustomers.single.name, 'Windows Authoritative Customer');
    expect(localCustomers.single.syncStatus, 'synced');

    final finalServerCustomers = await serverRepository.getAll();
    expect(finalServerCustomers.single.name, 'Windows Authoritative Customer');
    expect(finalServerCustomers.single.syncStatus, 'pending');
  });

  test('syncs a bill and all line items from Android to Windows', () async {
    final clientCustomers = CustomerRepository(database: clientDatabase);
    final clientBills = BillRepository(database: clientDatabase);
    final serverCustomers = CustomerRepository(database: serverDatabase);
    final serverBills = BillRepository(database: serverDatabase);

    final customer = makeCustomer(
      uuid: 'bill-push-customer',
      name: 'Bill Push Customer',
    );

    await clientCustomers.insert(customer);
    await syncWithRealHttpClient();

    final localCustomer = (await clientCustomers.getAll()).single;

    final bill = makeBill(
      uuid: 'bill-push',
      customerId: localCustomer.id!,
      customerUuid: customer.uuid,
      billNumber: 'INV-1001',
      amountPaidPaise: 50000,
      notes: 'Embroidery order',
    );

    final items = [
      makeItem(
        uuid: 'bill-push-item-1',
        description: 'Blouse embroidery',
        quantity: 2,
        ratePaise: 50000,
        amountPaise: 100000,
      ),
      makeItem(
        uuid: 'bill-push-item-2',
        description: 'Border embroidery',
        quantity: 1,
        ratePaise: 50000,
        amountPaise: 50000,
      ),
    ];

    await clientBills.insert(bill: bill, items: items);

    final result = await syncWithRealHttpClient();

    expect(result.connected, isTrue);
    expect(result.billsPushed, 1);

    final localBill = (await clientBills.getAll()).single;
    expect(localBill.uuid, bill.uuid);
    expect(localBill.syncStatus, 'synced');
    expect(localBill.customerUuid, customer.uuid);

    final localItems = await clientBills.getItems(localBill.id!);
    expect(localItems, hasLength(2));

    final serverCustomer = (await serverCustomers.getAll()).single;
    final serverBill = (await serverBills.getAll()).single;
    final serverItems = await serverBills.getItems(serverBill.id!);

    expect(serverCustomer.uuid, customer.uuid);
    expect(serverBill.uuid, bill.uuid);
    expect(serverBill.billNumber, 'INV-1001');
    expect(serverBill.amountPaidPaise, 50000);
    expect(serverBill.notes, 'Embroidery order');
    expect(serverBill.customerUuid, customer.uuid);
    expect(serverBill.customerId, serverCustomer.id);
    expect(serverItems, hasLength(2));
    expect(serverItems.map((item) => item.uuid), containsAll([
      'bill-push-item-1',
      'bill-push-item-2',
    ]));
    expect(serverItems.map((item) => item.description), containsAll([
      'Blouse embroidery',
      'Border embroidery',
    ]));
  });

  test('pulls a Windows bill and its line items into Android', () async {
    final clientBills = BillRepository(database: clientDatabase);
    final serverCustomers = CustomerRepository(database: serverDatabase);
    final serverBills = BillRepository(database: serverDatabase);

    final customer = makeCustomer(
      uuid: 'bill-pull-customer',
      name: 'Bill Pull Customer',
      syncStatus: 'synced',
    );

    await serverCustomers.insert(customer);
    await serverCustomers.markSynced(customer.uuid);
    await syncWithRealHttpClient();

    final localCustomer = (await CustomerRepository(database: clientDatabase).getAll()).single;

    final serverCustomer = (await serverCustomers.getAll()).single;
    final bill = makeBill(
      uuid: 'bill-pull',
      customerId: serverCustomer.id!,
      customerUuid: serverCustomer.uuid,
      billNumber: 'INV-2001',
      syncStatus: 'synced',
    );

    await serverBills.insert(
      bill: bill,
      items: [
        makeItem(
          uuid: 'bill-pull-item-1',
          description: 'Saree embroidery',
          quantity: 1,
          ratePaise: 150000,
          amountPaise: 150000,
        ),
      ],
    );
    await serverBills.markSynced(bill.uuid);

    final result = await syncWithRealHttpClient();

    expect(result.connected, isTrue);
    expect(result.billsPushed, 0);
    expect(result.billsPulled, 1);

    final localBills = await clientBills.getAll();
    expect(localBills, hasLength(1));
    expect(localBills.single.uuid, bill.uuid);
    expect(localBills.single.billNumber, 'INV-2001');
    expect(localBills.single.syncStatus, 'synced');
    expect(localBills.single.customerId, localCustomer.id);
    expect(localBills.single.customerUuid, customer.uuid);

    final localItems = await clientBills.getItems(localBills.single.id!);
    expect(localItems, hasLength(1));
    expect(localItems.single.uuid, 'bill-pull-item-1');
    expect(localItems.single.description, 'Saree embroidery');
    expect(localItems.single.quantity, 1);
    expect(localItems.single.ratePaise, 150000);
    expect(localItems.single.amountPaise, 150000);
  });

  test('replaces a synced bill and its items when Windows sends changes',
      () async {
    final clientBills = BillRepository(database: clientDatabase);
    final serverCustomers = CustomerRepository(database: serverDatabase);
    final serverBills = BillRepository(database: serverDatabase);

    final customer = makeCustomer(
      uuid: 'bill-update-customer',
      name: 'Bill Update Customer',
      syncStatus: 'synced',
    );

    await serverCustomers.insert(customer);
    await serverCustomers.markSynced(customer.uuid);
    await syncWithRealHttpClient();

    final serverCustomer = (await serverCustomers.getAll()).single;
    final originalBill = makeBill(
      uuid: 'bill-update',
      customerId: serverCustomer.id!,
      customerUuid: serverCustomer.uuid,
      billNumber: 'INV-3001',
      syncStatus: 'synced',
      notes: 'Original bill',
    );

    await serverBills.insert(
      bill: originalBill,
      items: [
        makeItem(
          uuid: 'bill-update-item-1',
          description: 'Original embroidery',
          quantity: 1,
          ratePaise: 100000,
          amountPaise: 100000,
        ),
      ],
    );
    await serverBills.markSynced(originalBill.uuid);

    final firstResult = await syncWithRealHttpClient();
    expect(firstResult.billsPulled, 1);

    final localBillBeforeUpdate = (await clientBills.getAll()).single;
    final localItemsBeforeUpdate =
        await clientBills.getItems(localBillBeforeUpdate.id!);
    expect(localItemsBeforeUpdate, hasLength(1));

    await serverBills.deleteAll();
    final updatedBill = originalBill.copyWith(
      syncStatus: 'synced',
      amountPaidPaise: 154000,
      notes: 'Updated by Windows',
      updatedAt: DateTime.utc(2026, 1, 2),
    );
    await serverBills.insert(
      bill: updatedBill,
      items: [
        makeItem(
          uuid: 'bill-update-item-2',
          description: 'Updated embroidery',
          quantity: 3,
          ratePaise: 60000,
          amountPaise: 180000,
        ),
      ],
    );
    await serverBills.markSynced(updatedBill.uuid);

    final secondResult = await syncWithRealHttpClient();

    expect(secondResult.connected, isTrue);
    expect(secondResult.billsPushed, 0);
    expect(secondResult.billsPulled, 1);

    final localBills = await clientBills.getAll();
    expect(localBills, hasLength(1));
    expect(localBills.single.uuid, originalBill.uuid);
    expect(localBills.single.notes, 'Updated by Windows');
    expect(localBills.single.amountPaidPaise, 154000);
    expect(localBills.single.syncStatus, 'synced');

    final localItems = await clientBills.getItems(localBills.single.id!);
    expect(localItems, hasLength(1));
    expect(localItems.single.uuid, 'bill-update-item-2');
    expect(localItems.single.description, 'Updated embroidery');
    expect(localItems.single.quantity, 3);
    expect(localItems.single.amountPaise, 180000);
  });

  test('rejected bill push stays pending after full sync', () async {
    final clientBills = BillRepository(database: clientDatabase);
    final serverCustomers = CustomerRepository(database: serverDatabase);
    final serverBills = BillRepository(database: serverDatabase);

    final customer = makeCustomer(
      uuid: 'bill-conflict-customer',
      name: 'Bill Conflict Customer',
    );

    await serverCustomers.insert(customer);
    await serverCustomers.markSynced(customer.uuid);
    await syncWithRealHttpClient();

    final serverCustomer = (await serverCustomers.getAll()).single;

    final serverBill = makeBill(
      uuid: 'bill-conflict',
      customerId: serverCustomer.id!,
      customerUuid: serverCustomer.uuid,
      billNumber: 'INV-4001',
      syncStatus: 'pending',
      notes: 'Windows version',
    );
    await serverBills.insert(
      bill: serverBill,
      items: [
        makeItem(
          uuid: 'bill-conflict-server-item',
          description: 'Windows item',
          quantity: 1,
          ratePaise: 100000,
          amountPaise: 100000,
        ),
      ],
    );

    await syncWithRealHttpClient();

    final localBillsBeforeEdit = await clientBills.getAll();
    expect(localBillsBeforeEdit, hasLength(1));
    final localBillId = localBillsBeforeEdit.single.id!;

    await clientDatabase.update(
      'bills',
      {
        'bill_number': 'INV-4002',
        'notes': 'Android version',
        'sync_status': 'pending',
      },
      where: 'id = ?',
      whereArgs: [localBillId],
    );

    await clientDatabase.delete(
      'bill_items',
      where: 'bill_id = ?',
      whereArgs: [localBillId],
    );

    await clientDatabase.insert('bill_items', {
      'uuid': 'bill-conflict-client-item',
      'bill_id': localBillId,
      'description': 'Android item',
      'quantity': 2,
      'rate_paise': 75000,
      'amount_paise': 150000,
    });

    final result = await syncWithRealHttpClient();

    expect(result.connected, isTrue);
    expect(result.billsPushed, 0);

    final localBills = await clientBills.getAll();
    expect(localBills, hasLength(1));
    expect(localBills.single.uuid, 'bill-conflict');
    expect(localBills.single.notes, 'Android version');
    expect(localBills.single.syncStatus, 'pending');

    final localItems = await clientBills.getItems(localBills.single.id!);
    expect(localItems, hasLength(1));
    expect(localItems.single.uuid, 'bill-conflict-client-item');

    final serverBillsList = await serverBills.getAll();
    expect(serverBillsList, hasLength(1));
    expect(serverBillsList.single.notes, 'Windows version');
    expect(serverBillsList.single.syncStatus, 'pending');

    final serverItems = await serverBills.getItems(serverBillsList.single.id!);
    expect(serverItems, hasLength(1));
    expect(serverItems.single.uuid, 'bill-conflict-server-item');
  });
}
