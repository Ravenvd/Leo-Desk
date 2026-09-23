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
import 'package:leo_desk/features/invoices/models/invoice.dart';
import 'package:leo_desk/features/invoices/models/invoice_item.dart';
import 'package:leo_desk/features/invoices/repositories/invoice_repository.dart';
import 'package:leo_desk/features/orders/models/order.dart';
import 'package:leo_desk/features/orders/models/order_item.dart';
import 'package:leo_desk/features/orders/repositories/order_item_repository.dart';
import 'package:leo_desk/features/orders/repositories/order_repository.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _RealHttpOverrides extends HttpOverrides {
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

  Customer makeCustomer(String uuid, String name) {
    final now = DateTime.utc(2026, 1, 1);
    return Customer(
      uuid: uuid,
      syncStatus: 'synced',
      name: name,
      phone: '9876543210',
      createdAt: now,
      updatedAt: now,
      customerType: 'Individual',
      serviceRequired: 'Embroidery',
    );
  }

  Order makeOrder({
    required String uuid,
    required int customerId,
    required String orderNumber,
    required DateTime updatedAt,
    String status = 'New',
    String syncStatus = 'synced',
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
      updatedAt: updatedAt,
    );
  }

  OrderItem makeOrderItem(int orderId) {
    final now = DateTime.utc(2026, 1, 1);
    return OrderItem(
      uuid: 'graph-roundtrip-order-item',
      orderId: orderId,
      workType: 'Embroidery',
      garmentType: 'Blouse',
      quantity: 2,
      unitPricePaise: 50000,
      notes: 'Order item',
      createdAt: now,
      updatedAt: now,
    );
  }

  Invoice makeInvoice({
    required int orderId,
    required String orderUuid,
    required int customerId,
    required String customerUuid,
    required DateTime updatedAt,
    String notes = 'Windows invoice',
    String syncStatus = 'synced',
  }) {
    final now = DateTime.utc(2026, 1, 1);
    return Invoice(
      uuid: 'graph-roundtrip-invoice',
      syncStatus: syncStatus,
      orderId: orderId,
      orderUuid: orderUuid,
      customerId: customerId,
      customerUuid: customerUuid,
      invoiceNumber: 'INV-000001',
      invoiceDate: now,
      subtotalPaise: 100000,
      totalPaise: 100000,
      notes: notes,
      createdAt: now,
      updatedAt: updatedAt,
    );
  }

  InvoiceItem makeInvoiceItem() {
    return InvoiceItem(
      uuid: 'graph-roundtrip-invoice-item',
      invoiceId: 0,
      description: 'Blouse embroidery',
      quantity: 1,
      ratePaise: 100000,
      amountPaise: 100000,
    );
  }

  Bill makeBill({
    required int orderId,
    required String orderUuid,
    required int customerId,
    required String customerUuid,
    required DateTime updatedAt,
    String notes = 'Windows bill',
    String syncStatus = 'synced',
  }) {
    final now = DateTime.utc(2026, 1, 1);
    return Bill(
      uuid: 'graph-roundtrip-bill',
      syncStatus: syncStatus,
      customerId: customerId,
      customerUuid: customerUuid,
      orderId: orderId,
      orderUuid: orderUuid,
      billNumber: 'BILL-000001',
      billDate: now,
      subtotalPaise: 100000,
      discountPaise: 0,
      taxPaise: 0,
      totalPaise: 100000,
      amountPaidPaise: 100000,
      notes: notes,
      createdAt: now,
      updatedAt: updatedAt,
    );
  }

  BillItem makeBillItem() {
    return BillItem(
      uuid: 'graph-roundtrip-bill-item',
      billId: 0,
      description: 'Blouse embroidery',
      quantity: 1,
      ratePaise: 100000,
      amountPaise: 100000,
    );
  }

  setUp(() async {
    testDirectory =
        await Directory.systemTemp.createTemp('leo_desk_sync_graph_test_');

    serverDatabase = await AppDatabase.openTestDatabase(
      path: testDirectory.path + Platform.pathSeparator + 'server.db',
    );
    clientDatabase = await AppDatabase.openTestDatabase(
      path: testDirectory.path + Platform.pathSeparator + 'client.db',
    );

    server = SyncServer(
      customerRepository: CustomerRepository(database: serverDatabase),
      billRepository: BillRepository(database: serverDatabase),
      invoiceRepository: InvoiceRepository(database: serverDatabase),
      orderRepository: OrderRepository(database: serverDatabase),
    );
    await server.start(port: 0);
  });

  tearDown(() async {
    await server.stop();
    await serverDatabase.close();
    await clientDatabase.close();
    await testDirectory.delete(recursive: true);
  });

  Future<SyncResult> sync() {
    final manager = SyncManager(
      client: SyncClient(
        serverAddress: '127.0.0.1',
        port: server.port!,
        token: SyncConfig.defaultToken,
      ),
      customerRepository: CustomerRepository(database: clientDatabase),
      billRepository: BillRepository(database: clientDatabase),
      invoiceRepository: InvoiceRepository(database: clientDatabase),
      orderRepository: OrderRepository(database: clientDatabase),
      saveLastSyncTime: (_) async {},
    );

    return HttpOverrides.runZoned(
      manager.sync,
      createHttpClient: (context) =>
          _RealHttpOverrides().createHttpClient(context),
    );
  }

  test('pulls exactly the 10 newest orders at the 10th/11th boundary',
      () async {
    final serverCustomers = CustomerRepository(database: serverDatabase);
    final serverOrders = OrderRepository(database: serverDatabase);
    final clientOrders = OrderRepository(database: clientDatabase);

    final customer = makeCustomer(
      'ten-order-boundary-customer',
      'Ten Order Boundary Customer',
    );
    await serverCustomers.insert(customer);
    await serverCustomers.markSynced(customer.uuid);

    final serverCustomer = (await serverCustomers.getAll()).single;

    for (var rank = 1; rank <= 11; rank++) {
      final order = makeOrder(
        uuid: 'ten-order-boundary-$rank',
        customerId: serverCustomer.id!,
        orderNumber: 'ORD-' + rank.toString().padLeft(6, '0'),
        updatedAt: DateTime.utc(2026, 1, 1).add(
          Duration(days: 12 - rank),
        ),
      );
      await serverOrders.insert(order);
      await serverOrders.markSynced(order.uuid);
    }

    final result = await sync();

    expect(result.connected, isTrue);
    expect(result.ordersPulled, 10);

    final localOrders = await clientOrders.getAll();
    expect(localOrders, hasLength(10));

    for (var rank = 1; rank <= 10; rank++) {
      expect(
        localOrders.any((order) => order.uuid == 'ten-order-boundary-$rank'),
        isTrue,
      );
    }

    expect(
      localOrders.any((order) => order.uuid == 'ten-order-boundary-11'),
      isFalse,
    );
  });

  test(
    'round-trips a Windows order graph through Android and back while preserving UUID identity and local foreign keys',
    () async {
      final serverCustomers = CustomerRepository(database: serverDatabase);
      final serverOrders = OrderRepository(database: serverDatabase);
      final serverOrderItems = OrderItemRepository(database: serverDatabase);
      final serverInvoices = InvoiceRepository(database: serverDatabase);
      final serverBills = BillRepository(database: serverDatabase);

      final clientCustomers = CustomerRepository(database: clientDatabase);
      final clientOrders = OrderRepository(database: clientDatabase);
      final clientOrderItems = OrderItemRepository(database: clientDatabase);
      final clientInvoices = InvoiceRepository(database: clientDatabase);
      final clientBills = BillRepository(database: clientDatabase);

      final customer = makeCustomer(
        'graph-roundtrip-customer',
        'Graph Round Trip Customer',
      );
      await serverCustomers.insert(customer);
      await serverCustomers.markSynced(customer.uuid);
      final serverCustomer = (await serverCustomers.getAll()).single;

      final windowsOrder = makeOrder(
        uuid: 'graph-roundtrip-order',
        customerId: serverCustomer.id!,
        orderNumber: 'ORD-000001',
        updatedAt: DateTime.utc(2026, 1, 1),
        status: 'In Progress',
      );
      await serverOrders.insert(windowsOrder);
      await serverOrders.markSynced(windowsOrder.uuid);
      final serverOrder = (await serverOrders.getAll()).single;

      await serverOrderItems.insert(makeOrderItem(serverOrder.id!));

      await serverInvoices.create(
        invoice: makeInvoice(
          orderId: serverOrder.id!,
          orderUuid: serverOrder.uuid,
          customerId: serverCustomer.id!,
          customerUuid: serverCustomer.uuid,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
        items: [makeInvoiceItem()],
      );
      await serverInvoices.markSynced('graph-roundtrip-invoice');

      await serverBills.insert(
        bill: makeBill(
          orderId: serverOrder.id!,
          orderUuid: serverOrder.uuid,
          customerId: serverCustomer.id!,
          customerUuid: serverCustomer.uuid,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
        items: [makeBillItem()],
      );
      await serverBills.markSynced('graph-roundtrip-bill');

      final serverInvoice = (await serverInvoices.getAll()).single;
      final serverBill = (await serverBills.getAll()).single;

      // Offset Android's local integer ids so the test proves UUID identity.
      final localDummyCustomer = makeCustomer(
        'local-dummy-customer',
        'Local Dummy',
      );
      await clientCustomers.insert(localDummyCustomer);
      await clientCustomers.markSynced(localDummyCustomer.uuid);

      final localDummyCustomerRow =
          (await clientCustomers.getAll()).single;
      final localDummyOrder = makeOrder(
        uuid: 'local-dummy-order',
        customerId: localDummyCustomerRow.id!,
        orderNumber: 'ORD-999999',
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      await clientOrders.insert(localDummyOrder);
      await clientOrders.markSynced(localDummyOrder.uuid);

      final first = await sync();
      expect(first.connected, isTrue);
      expect(first.ordersPulled, 1);
      expect(first.invoicesPulled, 1);
      expect(first.billsPulled, 1);

      final localCustomer =
          (await clientCustomers.getAll()).singleWhere(
        (row) => row.uuid == customer.uuid,
      );
      final localOrder =
          (await clientOrders.getAll()).singleWhere(
        (row) => row.uuid == windowsOrder.uuid,
      );
      final localInvoice = (await clientInvoices.getAll()).single;
      final localBill = (await clientBills.getAll()).single;

      expect(localOrder.uuid, serverOrder.uuid);
      expect(localInvoice.uuid, serverInvoice.uuid);
      expect(localBill.uuid, serverBill.uuid);
      expect(localOrder.id, isNot(serverOrder.id));

      expect(localInvoice.orderId, localOrder.id);
      expect(localInvoice.customerId, localCustomer.id);
      expect(localBill.orderId, localOrder.id);
      expect(localBill.customerId, localCustomer.id);

      final localOrderItems =
          await clientOrderItems.getByOrder(localOrder.id!);
      final localInvoiceItems =
          await clientInvoices.getItems(localInvoice.id!);
      final localBillItems =
          await clientBills.getItems(localBill.id!);

      expect(localOrderItems.single.uuid, 'graph-roundtrip-order-item');
      expect(localOrderItems.single.orderId, localOrder.id);
      expect(localInvoiceItems.single.uuid, 'graph-roundtrip-invoice-item');
      expect(localInvoiceItems.single.invoiceId, localInvoice.id);
      expect(localBillItems.single.uuid, 'graph-roundtrip-bill-item');
      expect(localBillItems.single.billId, localBill.id);

      // Android -> Windows: edit every root node.
      await clientDatabase.update(
        'orders',
        {
          'status': 'Completed',
          'updated_at': DateTime.utc(2026, 1, 2).toIso8601String(),
          'sync_status': 'pending',
        },
        where: 'uuid = ?',
        whereArgs: [windowsOrder.uuid],
      );
      await clientDatabase.update(
        'invoices',
        {
          'notes': 'Android invoice edit',
          'updated_at': DateTime.utc(2026, 1, 2).toIso8601String(),
          'sync_status': 'pending',
        },
        where: 'uuid = ?',
        whereArgs: [serverInvoice.uuid],
      );
      await clientDatabase.update(
        'bills',
        {
          'notes': 'Android bill edit',
          'updated_at': DateTime.utc(2026, 1, 2).toIso8601String(),
          'sync_status': 'pending',
        },
        where: 'uuid = ?',
        whereArgs: [serverBill.uuid],
      );

      final pushed = await sync();
      expect(pushed.connected, isTrue);
      expect(pushed.ordersPushed, 1);
      expect(pushed.invoicesPushed, 1);
      expect(pushed.billsPushed, 1);

      final pushedServerOrder =
          (await serverOrders.getAll()).singleWhere(
        (row) => row.uuid == windowsOrder.uuid,
      );
      final pushedServerInvoice =
          (await serverInvoices.getAll()).singleWhere(
        (row) => row.uuid == serverInvoice.uuid,
      );
      final pushedServerBill =
          (await serverBills.getAll()).singleWhere(
        (row) => row.uuid == serverBill.uuid,
      );

      expect(pushedServerOrder.status, 'Completed');
      expect(pushedServerInvoice.notes, 'Android invoice edit');
      expect(pushedServerBill.notes, 'Android bill edit');

      // Windows -> Android: Windows makes the next canonical edit.
      await serverDatabase.update(
        'orders',
        {
          'status': 'Ready',
          'updated_at': DateTime.utc(2026, 1, 3).toIso8601String(),
          'sync_status': 'synced',
        },
        where: 'uuid = ?',
        whereArgs: [windowsOrder.uuid],
      );
      await serverDatabase.update(
        'invoices',
        {
          'notes': 'Windows final invoice',
          'updated_at': DateTime.utc(2026, 1, 3).toIso8601String(),
          'sync_status': 'synced',
        },
        where: 'uuid = ?',
        whereArgs: [serverInvoice.uuid],
      );
      await serverDatabase.update(
        'bills',
        {
          'notes': 'Windows final bill',
          'updated_at': DateTime.utc(2026, 1, 3).toIso8601String(),
          'sync_status': 'synced',
        },
        where: 'uuid = ?',
        whereArgs: [serverBill.uuid],
      );

      final pulled = await sync();
      expect(pulled.connected, isTrue);
      expect(pulled.ordersPulled, 1);
      expect(pulled.invoicesPulled, 1);
      expect(pulled.billsPulled, 1);

      final finalOrder =
          (await clientOrders.getAll()).singleWhere(
        (row) => row.uuid == windowsOrder.uuid,
      );
      final finalInvoice =
          (await clientInvoices.getAll()).singleWhere(
        (row) => row.uuid == serverInvoice.uuid,
      );
      final finalBill =
          (await clientBills.getAll()).singleWhere(
        (row) => row.uuid == serverBill.uuid,
      );

      expect(finalOrder.status, 'Ready');
      expect(finalInvoice.notes, 'Windows final invoice');
      expect(finalBill.notes, 'Windows final bill');

      expect(finalOrder.uuid, serverOrder.uuid);
      expect(finalInvoice.orderUuid, finalOrder.uuid);
      expect(finalInvoice.customerUuid, localCustomer.uuid);
      expect(finalInvoice.orderId, finalOrder.id);
      expect(finalInvoice.customerId, localCustomer.id);
      expect(finalBill.orderUuid, finalOrder.uuid);
      expect(finalBill.customerUuid, localCustomer.uuid);
      expect(finalBill.orderId, finalOrder.id);
      expect(finalBill.customerId, localCustomer.id);

      final finalOrderItems =
          await clientOrderItems.getByOrder(finalOrder.id!);
      final finalInvoiceItems =
          await clientInvoices.getItems(finalInvoice.id!);
      final finalBillItems =
          await clientBills.getItems(finalBill.id!);

      expect(finalOrderItems.single.uuid, 'graph-roundtrip-order-item');
      expect(finalOrderItems.single.orderId, finalOrder.id);
      expect(finalInvoiceItems.single.uuid, 'graph-roundtrip-invoice-item');
      expect(finalInvoiceItems.single.invoiceId, finalInvoice.id);
      expect(finalBillItems.single.uuid, 'graph-roundtrip-bill-item');
      expect(finalBillItems.single.billId, finalBill.id);
    },
  );
}
