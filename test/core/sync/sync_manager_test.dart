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
import 'package:leo_desk/features/expenses/repositories/expense_repository.dart';
import 'package:leo_desk/features/invoices/models/invoice.dart';
import 'package:leo_desk/features/invoices/models/invoice_item.dart';
import 'package:leo_desk/features/invoices/repositories/invoice_repository.dart';
import 'package:leo_desk/features/inventory/models/asset.dart';
import 'package:leo_desk/features/inventory/models/consumable.dart';
import 'package:leo_desk/features/inventory/repositories/asset_repository.dart';
import 'package:leo_desk/features/inventory/repositories/consumable_repository.dart';
import 'package:leo_desk/features/inventory/repositories/maintenance_repository.dart';
import 'package:leo_desk/features/orders/models/order.dart';
import 'package:leo_desk/features/orders/models/order_item.dart';
import 'package:leo_desk/features/orders/repositories/order_item_repository.dart';
import 'package:leo_desk/features/orders/repositories/order_repository.dart';
import 'package:leo_desk/features/staff/repositories/staff_repository.dart';
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
    );
  }

  Invoice makeInvoice({
    required String uuid,
    required int orderId,
    required String orderUuid,
    required int customerId,
    required String customerUuid,
    String syncStatus = 'pending',
    String invoiceNumber = 'INV-000001',
  }) {
    final now = DateTime.utc(2026, 1, 1);
    return Invoice(
      uuid: uuid,
      syncStatus: syncStatus,
      orderId: orderId,
      orderUuid: orderUuid,
      customerId: customerId,
      customerUuid: customerUuid,
      invoiceNumber: invoiceNumber,
      invoiceDate: now,
      subtotalPaise: 100000,
      totalPaise: 100000,
      notes: 'Invoice notes',
      createdAt: now,
      updatedAt: now,
    );
  }

  InvoiceItem makeInvoiceItem({
    required String uuid,
    required String description,
  }) {
    return InvoiceItem(
      uuid: uuid,
      invoiceId: 0,
      description: description,
      quantity: 1,
      ratePaise: 100000,
      amountPaise: 100000,
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

  Order makeOrder({
    required String uuid,
    required int customerId,
    required String orderNumber,
    String syncStatus = 'pending',
    String status = 'New',
  }) {
    final now = DateTime.utc(2026, 1, 1);
    return Order(
      uuid: uuid,
      syncStatus: syncStatus,
      orderNumber: orderNumber,
      customerId: customerId,
      orderDate: now,
      expectedDeliveryDate: now.add(const Duration(days: 5)),
      stitchingRequired: true,
      stitchingPricePaise: 25000,
      status: status,
      notes: 'Order notes',
      createdAt: now,
      updatedAt: now,
    );
  }

  OrderItem makeOrderItem({
    required String uuid,
    required int orderId,
    required String workType,
    required String garmentType,
  }) {
    final now = DateTime.utc(2026, 1, 1);
    return OrderItem(
      uuid: uuid,
      orderId: orderId,
      workType: workType,
      garmentType: garmentType,
      quantity: 2,
      unitPricePaise: 50000,
      notes: 'Item notes',
      createdAt: now,
      updatedAt: now,
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
      invoiceRepository: InvoiceRepository(database: serverDatabase),
      expenseRepository: ExpenseRepository(database: serverDatabase),
      orderRepository: OrderRepository(database: serverDatabase),
      assetRepository: AssetRepository(database: serverDatabase),
      maintenanceRepository: MaintenanceRepository(database: serverDatabase),
      consumableRepository: ConsumableRepository(database: serverDatabase),
      staffRepository: StaffRepository(database: serverDatabase),
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
      invoiceRepository: InvoiceRepository(database: clientDatabase),
      expenseRepository: ExpenseRepository(database: clientDatabase),
      orderRepository: OrderRepository(database: clientDatabase),
      assetRepository: AssetRepository(database: clientDatabase),
      maintenanceRepository: MaintenanceRepository(database: clientDatabase),
      consumableRepository: ConsumableRepository(database: clientDatabase),
      staffRepository: StaffRepository(database: clientDatabase),
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
    // The pull acknowledgement marks the Windows copy as synced after the
    // Android client successfully applies it.
    expect(finalServerCustomers.single.syncStatus, 'synced');
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

    final localCustomer =
        (await CustomerRepository(database: clientDatabase).getAll()).single;

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

  test('Windows pending bill remains canonical over Android edits', () async {
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
      syncStatus: 'synced',
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

    // First sync establishes the shared bill on both sides. Windows is then
    // marked pending to represent a Windows-side edit. A same-UUID Android
    // push must receive the complete Windows record as the canonical version.
    await syncWithRealHttpClient();
    await serverDatabase.update(
      'bills',
      {'sync_status': 'pending'},
      where: 'uuid = ?',
      whereArgs: [serverBill.uuid],
    );

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
    expect(result.billsPushed, 1);

    final localBills = await clientBills.getAll();
    expect(localBills, hasLength(1));
    expect(localBills.single.uuid, 'bill-conflict');
    expect(localBills.single.billNumber, 'INV-4001');
    expect(localBills.single.notes, 'Windows version');
    expect(localBills.single.syncStatus, 'synced');

    final localItems = await clientBills.getItems(localBills.single.id!);
    expect(localItems, hasLength(1));
    expect(localItems.single.uuid, 'bill-conflict-server-item');
    expect(localItems.single.description, 'Windows item');

    final serverBillsList = await serverBills.getAll();
    expect(serverBillsList, hasLength(1));
    expect(serverBillsList.single.notes, 'Windows version');
    expect(serverBillsList.single.syncStatus, 'synced');

    final serverItems = await serverBills.getItems(serverBillsList.single.id!);
    expect(serverItems, hasLength(1));
    expect(serverItems.single.uuid, 'bill-conflict-server-item');
  });

  test('syncs an order, invoice, and bill as one UUID-rooted graph', () async {
    final clientCustomers = CustomerRepository(database: clientDatabase);
    final clientOrders = OrderRepository(database: clientDatabase);
    final clientOrderItems = OrderItemRepository(database: clientDatabase);
    final clientInvoices = InvoiceRepository(database: clientDatabase);
    final clientBills = BillRepository(database: clientDatabase);
    final serverOrders = OrderRepository(database: serverDatabase);
    final serverOrderItems = OrderItemRepository(database: serverDatabase);
    final serverInvoices = InvoiceRepository(database: serverDatabase);
    final serverBills = BillRepository(database: serverDatabase);

    final customer = makeCustomer(
      uuid: 'graph-customer',
      name: 'Graph Customer',
    );
    await clientCustomers.insert(customer);
    await syncWithRealHttpClient();

    final localCustomer = (await clientCustomers.getAll()).single;
    final order = makeOrder(
      uuid: 'graph-order',
      customerId: localCustomer.id!,
      orderNumber: 'ORD-000001',
      status: 'In Progress',
    );
    await clientOrders.insert(order);
    final localOrder = (await clientOrders.getAll()).single;

    await clientOrderItems.insert(
      makeOrderItem(
        uuid: 'graph-order-item',
        orderId: localOrder.id!,
        workType: 'Embroidery',
        garmentType: 'Blouse',
      ),
    );

    final invoice = makeInvoice(
      uuid: 'graph-invoice',
      orderId: localOrder.id!,
      orderUuid: localOrder.uuid,
      customerId: localCustomer.id!,
      customerUuid: localCustomer.uuid,
    );
    await clientInvoices.create(
      invoice: invoice,
      items: [
        makeInvoiceItem(
          uuid: 'graph-invoice-item',
          description: 'Blouse embroidery',
        ),
      ],
    );

    final bill = makeBill(
      uuid: 'graph-bill',
      customerId: localCustomer.id!,
      customerUuid: localCustomer.uuid,
      billNumber: 'INV-000001',
      amountPaidPaise: 100000,
    ).copyWith(
      orderId: localOrder.id,
      orderUuid: localOrder.uuid,
      subtotalPaise: 100000,
      discountPaise: 0,
      taxPaise: 0,
      totalPaise: 100000,
      amountPaidPaise: 100000,
    );
    await clientBills.insert(
      bill: bill,
      items: [
        makeItem(
          uuid: 'graph-bill-item',
          description: 'Blouse embroidery',
          quantity: 1,
          ratePaise: 100000,
          amountPaise: 100000,
        ),
      ],
    );

    final result = await syncWithRealHttpClient();

    expect(result.ordersPushed, 1);
    expect(result.invoicesPushed, 1);
    expect(result.billsPushed, 1);

    final serverOrder = (await serverOrders.getAll()).single;
    final serverInvoice = (await serverInvoices.getAll()).single;
    final serverBill = (await serverBills.getAll()).single;

    expect(serverOrder.uuid, 'graph-order');
    expect(serverInvoice.orderUuid, serverOrder.uuid);
    expect(serverInvoice.customerUuid, customer.uuid);
    expect(serverBill.orderUuid, serverOrder.uuid);
    expect(serverBill.customerUuid, customer.uuid);

    final syncedOrderItems = await serverOrderItems.getByOrder(serverOrder.id!);
    final serverInvoiceItems = await serverInvoices.getItems(serverInvoice.id!);
    final serverBillItems = await serverBills.getItems(serverBill.id!);

    expect(syncedOrderItems.single.uuid, 'graph-order-item');
    expect(syncedOrderItems.single.orderId, serverOrder.id);
    expect(serverInvoiceItems.single.uuid, 'graph-invoice-item');
    expect(serverInvoiceItems.single.invoiceId, serverInvoice.id);
    expect(serverBillItems.single.uuid, 'graph-bill-item');
    expect(serverBillItems.single.billId, serverBill.id);
  });


  test('preserves a colliding local order graph alongside Windows canonical data', () async {
    final clientCustomers = CustomerRepository(database: clientDatabase);
    final clientOrders = OrderRepository(database: clientDatabase);
    final clientOrderItems = OrderItemRepository(database: clientDatabase);
    final clientInvoices = InvoiceRepository(database: clientDatabase);
    final clientBills = BillRepository(database: clientDatabase);
    final serverCustomers = CustomerRepository(database: serverDatabase);
    final serverOrders = OrderRepository(database: serverDatabase);
    final serverOrderItems = OrderItemRepository(database: serverDatabase);
    final serverInvoices = InvoiceRepository(database: serverDatabase);
    final serverBills = BillRepository(database: serverDatabase);

    final customer = makeCustomer(
      uuid: 'graph-reconcile-customer',
      name: 'Graph Reconcile Customer',
      syncStatus: 'synced',
    );
    await serverCustomers.insert(customer);
    await serverCustomers.markSynced(customer.uuid);
    await syncWithRealHttpClient();

    final serverCustomer = (await serverCustomers.getAll()).single;
    final canonicalOrder = makeOrder(
      uuid: 'canonical-graph-order',
      customerId: serverCustomer.id!,
      orderNumber: 'ORD-000001',
      syncStatus: 'synced',
      status: 'In Progress',
    );
    await serverOrders.insert(canonicalOrder);
    await serverOrders.markSynced(canonicalOrder.uuid);
    final serverOrder = (await serverOrders.getAll()).single;

    await serverOrderItems.insert(
      makeOrderItem(
        uuid: 'canonical-order-item',
        orderId: serverOrder.id!,
        workType: 'Embroidery',
        garmentType: 'Blouse',
      ),
    );

    final canonicalInvoice = makeInvoice(
      uuid: 'canonical-invoice',
      orderId: serverOrder.id!,
      orderUuid: serverOrder.uuid,
      customerId: serverCustomer.id!,
      customerUuid: serverCustomer.uuid,
      syncStatus: 'synced',
    );
    await serverInvoices.create(
      invoice: canonicalInvoice,
      items: [
        makeInvoiceItem(
          uuid: 'canonical-invoice-item',
          description: 'Canonical blouse embroidery',
        ),
      ],
    );
    await serverInvoices.markSynced(canonicalInvoice.uuid);

    final canonicalBill = makeBill(
      uuid: 'canonical-bill',
      customerId: serverCustomer.id!,
      customerUuid: serverCustomer.uuid,
      billNumber: 'INV-000002',
      syncStatus: 'synced',
      amountPaidPaise: 100000,
    ).copyWith(
      orderId: serverOrder.id,
      orderUuid: serverOrder.uuid,
      subtotalPaise: 100000,
      discountPaise: 0,
      taxPaise: 0,
      totalPaise: 100000,
      amountPaidPaise: 100000,
    );
    await serverBills.insert(
      bill: canonicalBill,
      items: [
        makeItem(
          uuid: 'canonical-bill-item',
          description: 'Canonical blouse embroidery',
          quantity: 1,
          ratePaise: 100000,
          amountPaise: 100000,
        ),
      ],
    );
    await serverBills.markSynced(canonicalBill.uuid);

    final localCustomer = (await clientCustomers.getAll()).single;
    final staleOrder = makeOrder(
      uuid: 'stale-graph-order',
      customerId: localCustomer.id!,
      orderNumber: 'ORD-000001',
      syncStatus: 'synced',
      status: 'In Progress',
    );
    await clientOrders.insert(staleOrder);
    final localStaleOrder = (await clientOrders.getAll()).single;

    await clientOrderItems.insert(
      makeOrderItem(
        uuid: 'stale-order-item',
        orderId: localStaleOrder.id!,
        workType: 'Aari',
        garmentType: 'Old blouse',
      ),
    );

    final staleInvoice = makeInvoice(
      uuid: 'stale-invoice',
      orderId: localStaleOrder.id!,
      orderUuid: localStaleOrder.uuid,
      customerId: localCustomer.id!,
      customerUuid: localCustomer.uuid,
      syncStatus: 'synced',
      invoiceNumber: 'INV-000002',
    );
    await clientInvoices.create(
      invoice: staleInvoice,
      items: [
        makeInvoiceItem(
          uuid: 'stale-invoice-item',
          description: 'Stale invoice item',
        ),
      ],
    );
    await clientInvoices.markSynced(staleInvoice.uuid);

    final staleBill = makeBill(
      uuid: 'stale-bill',
      customerId: localCustomer.id!,
      customerUuid: localCustomer.uuid,
      billNumber: 'INV-000001',
      syncStatus: 'synced',
      amountPaidPaise: 100000,
    ).copyWith(
      orderId: localStaleOrder.id,
      orderUuid: localStaleOrder.uuid,
      subtotalPaise: 100000,
      discountPaise: 0,
      taxPaise: 0,
      totalPaise: 100000,
      amountPaidPaise: 100000,
    );
    await clientBills.insert(
      bill: staleBill,
      items: [
        makeItem(
          uuid: 'stale-bill-item',
          description: 'Stale bill item',
          quantity: 1,
          ratePaise: 100000,
          amountPaise: 100000,
        ),
      ],
    );
    await clientBills.markSynced(staleBill.uuid);

    final result = await syncWithRealHttpClient();

    expect(result.connected, isTrue);
    expect(result.ordersPushed, 1);
    expect(result.ordersPulled, 2);
    expect(result.invoicesPulled, 1);
    expect(result.billsPulled, 1);

    final localOrders = await clientOrders.getAll();
    expect(localOrders, hasLength(2));
    final localCanonicalOrder = localOrders.singleWhere(
      (order) => order.uuid == canonicalOrder.uuid,
    );
    final reconciledStaleOrder = localOrders.singleWhere(
      (order) => order.uuid == staleOrder.uuid,
    );
    expect(localCanonicalOrder.orderNumber, 'ORD-000001');
    expect(reconciledStaleOrder.orderNumber, 'ORD-000001A');

    final canonicalOrderItems =
        await clientOrderItems.getByOrder(localCanonicalOrder.id!);
    expect(canonicalOrderItems, hasLength(1));
    expect(canonicalOrderItems.single.uuid, 'canonical-order-item');

    final staleOrderItems =
        await clientOrderItems.getByOrder(reconciledStaleOrder.id!);
    expect(staleOrderItems, hasLength(1));
    expect(staleOrderItems.single.uuid, 'stale-order-item');

    final localInvoices = await clientInvoices.getAll();
    expect(localInvoices, hasLength(2));
    final pulledInvoice = localInvoices.singleWhere(
      (invoice) => invoice.uuid == canonicalInvoice.uuid,
    );
    final preservedInvoice = localInvoices.singleWhere(
      (invoice) => invoice.uuid == staleInvoice.uuid,
    );
    expect(pulledInvoice.orderUuid, canonicalOrder.uuid);
    expect(pulledInvoice.orderId, localCanonicalOrder.id);
    expect(preservedInvoice.orderUuid, staleOrder.uuid);
    expect(preservedInvoice.orderId, reconciledStaleOrder.id);
    expect(
      (await clientInvoices.getItems(pulledInvoice.id!)).single.uuid,
      'canonical-invoice-item',
    );
    expect(
      (await clientInvoices.getItems(preservedInvoice.id!)).single.uuid,
      'stale-invoice-item',
    );

    final localBills = await clientBills.getAll();
    expect(localBills, hasLength(2));
    final pulledBill = localBills.singleWhere(
      (bill) => bill.uuid == canonicalBill.uuid,
    );
    final preservedBill = localBills.singleWhere(
      (bill) => bill.uuid == staleBill.uuid,
    );
    expect(pulledBill.orderUuid, canonicalOrder.uuid);
    expect(pulledBill.orderId, localCanonicalOrder.id);
    expect(preservedBill.orderUuid, staleOrder.uuid);
    expect(preservedBill.orderId, reconciledStaleOrder.id);
    expect(
      (await clientBills.getItems(pulledBill.id!)).single.uuid,
      'canonical-bill-item',
    );
    expect(
      (await clientBills.getItems(preservedBill.id!)).single.uuid,
      'stale-bill-item',
    );
  });

  test('pulls the complete Windows order history, not just a recent page', () async {
    final serverCustomers = CustomerRepository(database: serverDatabase);
    final serverOrders = OrderRepository(database: serverDatabase);
    final clientOrders = OrderRepository(database: clientDatabase);

    final customer = makeCustomer(
      uuid: 'recent-update-window-customer',
      name: 'Recent Update Window Customer',
      syncStatus: 'synced',
    );
    await serverCustomers.insert(customer);
    await serverCustomers.markSynced(customer.uuid);
    await syncWithRealHttpClient();

    final serverCustomer = (await serverCustomers.getAll()).single;
    final target = makeOrder(
      uuid: 'recently-updated-old-order',
      customerId: serverCustomer.id!,
      orderNumber: 'ORD-000001',
      syncStatus: 'synced',
    ).copyWith(
      updatedAt: DateTime.utc(2026, 1, 2),
    );
    await serverOrders.insert(target);
    await serverOrders.markSynced(target.uuid);

    for (var i = 2; i <= 101; i++) {
      final order = makeOrder(
        uuid: 'older-window-order-$i',
        customerId: serverCustomer.id!,
        orderNumber: 'ORD-${i.toString().padLeft(6, '0')}',
        syncStatus: 'synced',
      );
      await serverOrders.insert(order);
      await serverOrders.markSynced(order.uuid);
    }

    final result = await syncWithRealHttpClient();

    expect(result.connected, isTrue);
    expect(result.ordersPulled, 101);

    final localOrders = await clientOrders.getAll();
    expect(localOrders, hasLength(101));
    final pulledTarget = localOrders.singleWhere((order) => order.uuid == target.uuid);
    expect(pulledTarget.updatedAt, target.updatedAt);
  });
  test('syncs an order and all line items from Android to Windows', () async {
    final clientCustomers = CustomerRepository(database: clientDatabase);
    final clientOrders = OrderRepository(database: clientDatabase);
    final clientOrderItems = OrderItemRepository(database: clientDatabase);
    final serverOrders = OrderRepository(database: serverDatabase);
    final serverOrderItems = OrderItemRepository(database: serverDatabase);

    final customer = makeCustomer(
      uuid: 'order-push-customer',
      name: 'Order Push Customer',
    );
    await clientCustomers.insert(customer);
    await syncWithRealHttpClient();

    final localCustomer = (await clientCustomers.getAll()).single;
    final order = makeOrder(
      uuid: 'order-push',
      customerId: localCustomer.id!,
      orderNumber: 'ORD-000001',
    );
    await clientOrders.insert(order);

    final localOrder = (await clientOrders.getAll()).single;
    await clientOrderItems.insert(
      makeOrderItem(
        uuid: 'order-push-item',
        orderId: localOrder.id!,
        workType: 'Embroidery',
        garmentType: 'Blouse',
      ),
    );

    final result = await syncWithRealHttpClient();

    expect(result.connected, isTrue);
    expect(result.ordersPushed, 1);

    final clientOrder = (await clientOrders.getAll()).single;
    expect(clientOrder.syncStatus, 'synced');

    final serverOrder = (await serverOrders.getAll()).single;
    expect(serverOrder.uuid, order.uuid);
    expect(serverOrder.orderNumber, 'ORD-000001');
    final serverCustomer = (await CustomerRepository(database: serverDatabase).getAll()).single;
    expect(serverOrder.customerId, serverCustomer.id);
    expect(serverOrder.stitchingPricePaise, 25000);

    final serverItems = await serverOrderItems.getByOrder(serverOrder.id!);
    expect(serverItems, hasLength(1));
    expect(serverItems.single.uuid, 'order-push-item');
    expect(serverItems.single.workType, 'Embroidery');
    expect(serverItems.single.garmentType, 'Blouse');
  });

  test('pulls a Windows order and its line items into Android', () async {
    final serverCustomers = CustomerRepository(database: serverDatabase);
    final serverOrders = OrderRepository(database: serverDatabase);
    final serverOrderItems = OrderItemRepository(database: serverDatabase);
    final clientOrders = OrderRepository(database: clientDatabase);
    final clientOrderItems = OrderItemRepository(database: clientDatabase);

    final customer = makeCustomer(
      uuid: 'order-pull-customer',
      name: 'Order Pull Customer',
      syncStatus: 'synced',
    );
    await serverCustomers.insert(customer);
    await serverCustomers.markSynced(customer.uuid);

    await syncWithRealHttpClient();

    final serverCustomer = (await serverCustomers.getAll()).single;
    final order = makeOrder(
      uuid: 'order-pull',
      customerId: serverCustomer.id!,
      orderNumber: 'ORD-000101',
      syncStatus: 'synced',
      status: 'In Progress',
    );
    await serverOrders.insert(order);
    await serverOrders.markSynced(order.uuid);

    final serverOrder = (await serverOrders.getAll()).single;
    await serverOrderItems.insert(
      makeOrderItem(
        uuid: 'order-pull-item',
        orderId: serverOrder.id!,
        workType: 'Aari',
        garmentType: 'Garment piece',
      ),
    );

    final result = await syncWithRealHttpClient();

    expect(result.connected, isTrue);
    expect(result.ordersPushed, 0);
    expect(result.ordersPulled, 1);

    final localOrders = await clientOrders.getAll();
    expect(localOrders, hasLength(1));
    expect(localOrders.single.uuid, order.uuid);
    expect(localOrders.single.orderNumber, 'ORD-000101');
    expect(localOrders.single.status, 'In Progress');
    expect(localOrders.single.syncStatus, 'synced');

    final localItems = await clientOrderItems.getByOrder(localOrders.single.id!);
    expect(localItems, hasLength(1));
    expect(localItems.single.uuid, 'order-pull-item');
    expect(localItems.single.workType, 'Aari');
    expect(localItems.single.garmentType, 'Garment piece');
  });

  test('does not delete a pending local order during reconciliation', () async {
    final clientCustomers = CustomerRepository(database: clientDatabase);
    final clientOrders = OrderRepository(database: clientDatabase);

    final customer = makeCustomer(
      uuid: 'pending-conflict-customer',
      name: 'Pending Conflict Customer',
      syncStatus: 'synced',
    );
    await clientCustomers.insert(customer);
    await clientCustomers.markSynced(customer.uuid);

    final localCustomer = (await clientCustomers.getAll()).single;
    final pendingOrder = makeOrder(
      uuid: 'pending-local-order',
      customerId: localCustomer.id!,
      orderNumber: 'ORD-000001',
      syncStatus: 'pending',
    );
    await clientOrders.insert(pendingOrder);

    final incomingOrder = makeOrder(
      uuid: 'windows-order',
      customerId: localCustomer.id!,
      orderNumber: 'ORD-000001',
      syncStatus: 'synced',
    );

    final applied = await clientOrders.upsertFromSync(
      incomingOrder,
      <OrderItem>[],
    );

    expect(applied, isFalse);

    final orders = await clientOrders.getAll();
    expect(orders, hasLength(1));
    expect(orders.single.uuid, 'pending-local-order');
    expect(orders.single.orderNumber, 'ORD-000001');
    expect(orders.single.syncStatus, 'pending');
  });

  test('preserves a distinct local order when Windows canonical number conflicts', () async {
    final clientCustomers = CustomerRepository(database: clientDatabase);
    final clientOrders = OrderRepository(database: clientDatabase);

    final customer = makeCustomer(
      uuid: 'order-reconcile-customer',
      name: 'Reconcile Customer',
      syncStatus: 'synced',
    );
    await clientCustomers.insert(customer);
    await clientCustomers.markSynced(customer.uuid);

    final localCustomer = (await clientCustomers.getAll()).single;
    final staleOrder = makeOrder(
      uuid: 'stale-local-order',
      customerId: localCustomer.id!,
      orderNumber: 'ORD-000001',
      syncStatus: 'synced',
    );
    await clientOrders.insert(staleOrder);
    await clientOrders.markSynced(staleOrder.uuid);

    final incomingOrder = makeOrder(
      uuid: 'windows-canonical-order',
      customerId: localCustomer.id!,
      orderNumber: 'ORD-000001',
      syncStatus: 'synced',
    );

    final applied = await clientOrders.upsertFromSync(
      incomingOrder,
      <OrderItem>[],
    );

    expect(applied, isFalse);

    final orders = await clientOrders.getAll();
    expect(orders, hasLength(1));
    expect(orders.single.uuid, 'stale-local-order');
    expect(orders.single.orderNumber, 'ORD-000001');
    expect(orders.single.syncStatus, 'synced');
  });

  test('suffixes a new offline order when Windows already uses its order number', () async {
    final clientCustomers = CustomerRepository(database: clientDatabase);
    final clientOrders = OrderRepository(database: clientDatabase);
    final serverCustomers = CustomerRepository(database: serverDatabase);
    final serverOrders = OrderRepository(database: serverDatabase);

    final customer = makeCustomer(
      uuid: 'order-number-collision-customer',
      name: 'Collision Customer',
    );
    await clientCustomers.insert(customer);
    await syncWithRealHttpClient();

    final serverCustomer = (await serverCustomers.getAll()).single;
    final windowsOrder = makeOrder(
      uuid: 'windows-existing-order',
      customerId: serverCustomer.id!,
      orderNumber: 'ORD-000001',
      syncStatus: 'synced',
    );
    await serverOrders.insert(windowsOrder);
    await serverOrders.markSynced(windowsOrder.uuid);

    final localCustomer = (await clientCustomers.getAll()).single;
    final androidOrder = makeOrder(
      uuid: 'android-collision-order',
      customerId: localCustomer.id!,
      orderNumber: 'ORD-000001',
      syncStatus: 'pending',
    );
    await clientOrders.insert(androidOrder);

    final result = await syncWithRealHttpClient();

    expect(result.connected, isTrue);
    expect(result.ordersPushed, 1);

    final localOrders = await clientOrders.getAll();
    final pushedOrder = localOrders.singleWhere(
      (order) => order.uuid == androidOrder.uuid,
    );
    expect(pushedOrder.orderNumber, 'ORD-000001A');
    expect(pushedOrder.syncStatus, 'synced');

    final serverOrdersAfter = await serverOrders.getAll();
    final serverOrder = serverOrdersAfter.singleWhere(
      (order) => order.uuid == androidOrder.uuid,
    );
    expect(serverOrder.orderNumber, 'ORD-000001A');
    expect(serverOrder.syncStatus, 'synced');

    expect(
      serverOrdersAfter.where((order) => order.orderNumber == 'ORD-000001'),
      hasLength(1),
    );
  });

  test(
    'pulls Windows consumables, spools and activity history by UUID',
    () async {
      final windowsInventory = ConsumableRepository(database: serverDatabase);
      final androidInventory = ConsumableRepository(database: clientDatabase);
      final now = DateTime.utc(2026, 10, 30);

      // Occupy a local integer ID so synced relationships must resolve by UUID.
      await androidInventory.insertConsumable(Consumable(
        uuid: 'android-local-id-offset',
        category: Consumable.categoryOils,
        name: 'Local-only oil',
        trackingType: Consumable.trackingQuantity,
        stockUnit: Consumable.unitMillilitres,
        createdAt: now,
        updatedAt: now,
      ));
      await androidInventory.markSyncRecordSynced(
        'consumables',
        'android-local-id-offset',
      );

      final beads = Consumable(
        uuid: 'windows-beads-sync',
        category: Consumable.categoryBeads,
        name: 'Red cut beads',
        trackingType: Consumable.trackingQuantity,
        stockUnit: Consumable.unitGrams,
        reorderLevel: 200,
        createdAt: now,
        updatedAt: now,
      );
      final thread = Consumable(
        uuid: 'windows-thread-sync',
        category: Consumable.categoryEmbroideryThread,
        name: 'Blue embroidery thread',
        trackingType: Consumable.trackingPercentage,
        stockUnit: Consumable.unitMetres,
        createdAt: now,
        updatedAt: now,
      );

      await windowsInventory.insertConsumable(beads);
      await windowsInventory.insertConsumable(thread);
      final savedBeads = await windowsInventory.getConsumableByUuid(beads.uuid);
      final savedThread = await windowsInventory.getConsumableByUuid(thread.uuid);
      await windowsInventory.recordStockIn(
        consumable: savedBeads!,
        quantity: 500,
        activityType: 'purchase',
        notes: 'Windows opening purchase',
      );
      await windowsInventory.addThreadSpool(
        consumable: savedThread!,
        approximateLengthM: 100,
        notes: 'Windows thread spool',
      );

      final result = await syncWithRealHttpClient();

      expect(result.connected, isTrue);
      expect(result.inventoryPulled, 5);

      final localBeads = await androidInventory.getConsumableByUuid(beads.uuid);
      expect(localBeads, isNotNull);
      expect(localBeads!.id, isNot(1));
      expect(await androidInventory.getCurrentStock(localBeads.id!), 500);

      final localThread = await androidInventory.getConsumableByUuid(thread.uuid);
      expect(localThread, isNotNull);
      final localSpools = await androidInventory.getSpools(localThread!.id!);
      expect(localSpools, hasLength(1));
      expect(localSpools.single.consumableUuid, thread.uuid);
      expect(localSpools.single.consumableId, localThread.id);

      final windowsRecords = await windowsInventory.getAllSyncRecords();
      expect(windowsRecords, hasLength(5));
      expect(
        windowsRecords.every((record) => record['sync_status'] == 'synced'),
        isTrue,
      );
    },
  );

  test(
    'pushes Android consumables and activity events without local IDs',
    () async {
    final androidInventory = ConsumableRepository(database: clientDatabase);
    final windowsInventory = ConsumableRepository(database: serverDatabase);
    final now = DateTime.utc(2026, 10, 30);
    final oil = Consumable(
      uuid: 'android-oil-sync',
      category: Consumable.categoryOils,
      name: 'Thread oil',
      trackingType: Consumable.trackingQuantity,
      stockUnit: Consumable.unitMillilitres,
      reorderLevel: 100,
      createdAt: now,
      updatedAt: now,
    );

    await androidInventory.insertConsumable(oil);
    final savedOil = (await androidInventory.getConsumables()).single;
    await androidInventory.recordStockIn(
      consumable: savedOil,
      quantity: 250,
      activityType: 'purchase',
    );

    final result = await syncWithRealHttpClient();

    expect(result.connected, isTrue);
    expect(result.inventoryPushed, 2);

    final windowsOil = (await windowsInventory.getConsumables()).single;
    expect(windowsOil.uuid, oil.uuid);
    expect(await windowsInventory.getCurrentStock(windowsOil.id!), 250);

    final windowsRecords = await windowsInventory.getAllSyncRecords();
    expect(windowsRecords, hasLength(2));
    expect(
      windowsRecords.every((record) => record['sync_status'] == 'synced'),
      isTrue,
    );

    final retry = await syncWithRealHttpClient();
    expect(retry.inventoryPushed, 0);
    expect((await windowsInventory.getAllSyncRecords()), hasLength(2));
  });

  test(
    'reconciles colliding local asset codes to Windows canonical codes',
    () async {
    final windowsAssets = AssetRepository(database: serverDatabase);
    final androidAssets = AssetRepository(database: clientDatabase);
    final now = DateTime.utc(2026, 10, 30);

    final windowsAsset = Asset(
      uuid: 'windows-canonical-asset',
      name: 'Windows machine',
      createdAt: now,
      updatedAt: now,
    );
    await windowsAssets.insert(windowsAsset);
    await windowsAssets.markSynced(windowsAsset.uuid);

    final androidAsset = Asset(
      uuid: 'android-offline-asset',
      name: 'Android machine',
      createdAt: now,
      updatedAt: now,
    );
    await androidAssets.insert(androidAsset);

    final result = await syncWithRealHttpClient();

    expect(result.connected, isTrue);
    expect(result.assetsPushed, 1);
    expect(result.assetsPulled, 2);

    final localAssets = await androidAssets.getAll();
    expect(localAssets, hasLength(2));
    expect(
      localAssets.singleWhere((asset) => asset.uuid == windowsAsset.uuid).assetCode,
      'AST-0001',
    );
    expect(
      localAssets.singleWhere((asset) => asset.uuid == androidAsset.uuid).assetCode,
      'AST-0001A',
    );
  });


  test('Windows asset fields win over a same-UUID Android edit', () async {
    final windowsAssets = AssetRepository(database: serverDatabase);
    final androidAssets = AssetRepository(database: clientDatabase);

    final windowsAsset = Asset(
      uuid: 'shared-asset-conflict',
      name: 'Windows machine',
      manufacturerModel: 'Windows model',
      createdAt: DateTime.utc(2026, 10, 30),
      updatedAt: DateTime.utc(2026, 10, 30),
    );
    await windowsAssets.insert(windowsAsset);

    final androidAsset = Asset(
      uuid: windowsAsset.uuid,
      name: 'Android attempted edit',
      manufacturerModel: 'Android model',
      createdAt: DateTime.utc(2026, 10, 30),
      updatedAt: DateTime.utc(2026, 10, 31),
    );
    await androidAssets.insert(androidAsset);

    final result = await syncWithRealHttpClient();

    expect(result.connected, isTrue);
    expect(result.assetsPushed, 1);

    final local = (await androidAssets.getAll()).single;
    final windows = (await windowsAssets.getAll()).single;
    expect(local.uuid, windowsAsset.uuid);
    expect(local.name, 'Windows machine');
    expect(local.manufacturerModel, 'Windows model');
    expect(local.syncStatus, Asset.syncStatusSynced);
    expect(windows.name, 'Windows machine');
    expect(windows.syncStatus, Asset.syncStatusSynced);
  });

  test(
    'Windows pending consumable edit wins over an Android conflict',
    () async {
    final windowsInventory = ConsumableRepository(database: serverDatabase);
    final androidInventory = ConsumableRepository(database: clientDatabase);
    final now = DateTime.utc(2026, 10, 30);

    await windowsInventory.insertConsumable(Consumable(
      uuid: 'shared-consumable-conflict',
      category: Consumable.categoryBeads,
      name: 'Windows version',
      trackingType: Consumable.trackingQuantity,
      stockUnit: Consumable.unitGrams,
      reorderLevel: 200,
      createdAt: now,
      updatedAt: now,
    ));
    await androidInventory.insertConsumable(Consumable(
      uuid: 'shared-consumable-conflict',
      category: Consumable.categoryBeads,
      name: 'Android offline edit',
      trackingType: Consumable.trackingQuantity,
      stockUnit: Consumable.unitGrams,
      reorderLevel: 100,
      createdAt: now,
      updatedAt: now,
    ));

    final result = await syncWithRealHttpClient();

    expect(result.connected, isTrue);
    expect(result.inventoryPushed, 0);
    expect(result.inventoryPulled, 1);

    final local = (await androidInventory.getConsumables()).single;
    final windows = (await windowsInventory.getConsumables()).single;
    expect(local.name, 'Windows version');
    expect(local.reorderLevel, 200);
    expect(local.syncStatus, 'synced');
    expect(windows.syncStatus, 'synced');
  });


}
