import 'package:flutter_test/flutter_test.dart';
import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/core/sync/sync_client.dart';
import 'package:leo_desk/core/sync/sync_config.dart';
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
import 'package:leo_desk/features/inventory/repositories/asset_repository.dart';
import 'package:leo_desk/features/inventory/repositories/consumable_repository.dart';
import 'package:leo_desk/features/inventory/repositories/maintenance_repository.dart';
import 'package:leo_desk/features/orders/models/order.dart';
import 'package:leo_desk/features/orders/repositories/order_repository.dart';
import 'package:leo_desk/features/staff/repositories/staff_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database database;
  late CustomerRepository customers;
  late OrderRepository orders;
  late InvoiceRepository invoices;
  late BillRepository bills;
  late SyncServer server;
  late SyncClient client;
  late Customer customer;
  late Map<String, Order> ordersByUuid;

  final now = DateTime.utc(2026, 11, 13, 10);

  Order makeOrder(String uuid, String number) => Order(
        uuid: uuid,
        syncStatus: 'synced',
        orderNumber: number,
        customerId: customer.id!,
        orderDate: now,
        expectedDeliveryDate: now.add(const Duration(days: 5)),
        stitchingRequired: true,
        stitchingPricePaise: 10000,
        status: 'New',
        createdAt: now,
        updatedAt: now,
      );

  Invoice makeInvoice({
    required String uuid,
    required String orderUuid,
    required String number,
    String notes = 'Invoice notes',
  }) {
    final order = ordersByUuid[orderUuid]!;
    return Invoice(
      uuid: uuid,
      syncStatus: 'pending',
      orderId: order.id!,
      orderUuid: orderUuid,
      customerId: customer.id!,
      customerUuid: customer.uuid,
      invoiceNumber: number,
      invoiceDate: now,
      subtotalPaise: 100000,
      totalPaise: 100000,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
  }

  InvoiceItem makeInvoiceItem(String uuid, {String description = 'Invoice item'}) =>
      InvoiceItem(
        uuid: uuid,
        invoiceId: 0,
        description: description,
        quantity: 1,
        ratePaise: 100000,
        amountPaise: 100000,
      );

  Bill makeBill({
    required String uuid,
    required String orderUuid,
    required String number,
    String notes = 'Bill notes',
  }) {
    final order = ordersByUuid[orderUuid]!;
    return Bill(
      uuid: uuid,
      syncStatus: 'pending',
      customerId: customer.id!,
      customerUuid: customer.uuid,
      orderId: order.id!,
      orderUuid: orderUuid,
      billNumber: number,
      billDate: now,
      subtotalPaise: 100000,
      totalPaise: 100000,
      amountPaidPaise: 0,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
  }

  BillItem makeBillItem(String uuid, {String description = 'Bill item'}) =>
      BillItem(
        uuid: uuid,
        billId: 0,
        description: description,
        quantity: 1,
        ratePaise: 100000,
        amountPaise: 100000,
      );

  setUp(() async {
    database = await AppDatabase.openTestDatabase();
    customers = CustomerRepository(database: database);
    orders = OrderRepository(database: database);
    invoices = InvoiceRepository(database: database);
    bills = BillRepository(database: database);

    customer = Customer(
      uuid: 'financial-sync-customer',
      syncStatus: 'synced',
      name: 'Financial Sync Customer',
      createdAt: now,
      updatedAt: now,
    );
    await customers.insert(customer);
    await customers.markSynced(customer.uuid);
    customer = (await customers.getAll()).single;

    ordersByUuid = {};
    for (var i = 1; i <= 4; i++) {
      final order = makeOrder('financial-sync-order-$i', 'ORD-00000$i');
      await orders.insert(order);
      await orders.markSynced(order.uuid);
      ordersByUuid[order.uuid] = (await orders.getAll()).singleWhere(
        (saved) => saved.uuid == order.uuid,
      );
    }

    server = SyncServer(
      customerRepository: customers,
      billRepository: bills,
      expenseRepository: ExpenseRepository(database: database),
      invoiceRepository: invoices,
      orderRepository: orders,
      assetRepository: AssetRepository(database: database),
      maintenanceRepository: MaintenanceRepository(database: database),
      consumableRepository: ConsumableRepository(database: database),
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

  Future<void> saveWindowsInvoice(Invoice invoice, InvoiceItem item) async {
    await invoices.create(invoice: invoice, items: [item]);
    await invoices.markSynced(invoice.uuid);
  }

  Future<void> saveWindowsBill(Bill bill, BillItem item) async {
    await bills.insert(bill: bill, items: [item]);
    await bills.markSynced(bill.uuid);
  }

  test('same invoice UUID returns the complete Windows invoice graph', () async {
    final windowsInvoice = makeInvoice(
      uuid: 'windows-canonical-invoice',
      orderUuid: 'financial-sync-order-1',
      number: 'INV-000032',
      notes: 'Windows invoice is canonical',
    );
    final windowsItem = makeInvoiceItem('windows-canonical-invoice-item');
    await saveWindowsInvoice(windowsInvoice, windowsItem);
    final saved = (await invoices.getAll()).single;

    final androidInvoice = windowsInvoice.copyWith(
      orderUuid: 'unknown-order',
      invoiceNumber: 'INV-999999',
      notes: 'Android attempted edit',
    );
    final response = await client.sendInvoice(
      SyncInvoice(
        invoice: androidInvoice,
        items: [makeInvoiceItem('android-replacement-invoice-item')],
      ),
    );

    expect(response, isNotNull);
    expect(response!['invoice_number'], 'INV-000032');
    expect(response['notes'], 'Windows invoice is canonical');
    expect(
      (response['items'] as List).single['uuid'],
      'windows-canonical-invoice-item',
    );

    final persisted = (await invoices.getAll()).single;
    expect(persisted.id, saved.id);
    expect(persisted.invoiceNumber, 'INV-000032');
    expect(persisted.notes, 'Windows invoice is canonical');
    expect(
      (await invoices.getItems(persisted.id!)).single.uuid,
      'windows-canonical-invoice-item',
    );
  });

  test('invoice collisions allocate stable A and B suffixes across devices',
      () async {
    await saveWindowsInvoice(
      makeInvoice(
        uuid: 'windows-invoice-base',
        orderUuid: 'financial-sync-order-1',
        number: 'INV-000032',
      ),
      makeInvoiceItem('windows-invoice-base-item'),
    );

    final incomingA = makeInvoice(
      uuid: 'android-invoice-a',
      orderUuid: 'financial-sync-order-2',
      number: 'INV-000032',
    );
    final itemA = makeInvoiceItem('android-invoice-a-item');
    final responseA = await client.sendInvoice(
      SyncInvoice(invoice: incomingA, items: [itemA]),
    );
    expect(responseA, isNotNull);
    expect(responseA!['invoice_number'], 'INV-000032A');

    final retryA = await client.sendInvoice(
      SyncInvoice(
        invoice: incomingA.copyWith(notes: 'Changed retry payload'),
        items: [makeInvoiceItem('android-invoice-a-retry-item')],
      ),
    );
    expect(retryA, isNotNull);
    expect(retryA!['invoice_number'], 'INV-000032A');
    expect(retryA['notes'], 'Invoice notes');
    expect(
      (retryA['items'] as List).single['uuid'],
      'android-invoice-a-item',
    );

    final responseB = await client.sendInvoice(
      SyncInvoice(
        invoice: makeInvoice(
          uuid: 'android-invoice-b',
          orderUuid: 'financial-sync-order-3',
          number: 'INV-000032',
        ),
        items: [makeInvoiceItem('android-invoice-b-item')],
      ),
    );
    expect(responseB, isNotNull);
    expect(responseB!['invoice_number'], 'INV-000032B');

    final saved = await invoices.getAll();
    expect(saved, hasLength(3));
    expect(
      saved.map((invoice) => invoice.invoiceNumber).toSet(),
      {'INV-000032', 'INV-000032A', 'INV-000032B'},
    );
    expect(
      (await invoices.getItems(
        saved.singleWhere((invoice) => invoice.uuid == incomingA.uuid).id!,
      ))
          .single
          .uuid,
      'android-invoice-a-item',
    );
  });

  test('a different invoice UUID cannot replace the invoice for an order',
      () async {
    await saveWindowsInvoice(
      makeInvoice(
        uuid: 'windows-invoice-for-order',
        orderUuid: 'financial-sync-order-1',
        number: 'INV-000040',
      ),
      makeInvoiceItem('windows-invoice-for-order-item'),
    );

    final response = await client.sendInvoice(
      SyncInvoice(
        invoice: makeInvoice(
          uuid: 'second-invoice-same-order',
          orderUuid: 'financial-sync-order-1',
          number: 'INV-000041',
        ),
        items: [makeInvoiceItem('second-invoice-same-order-item')],
      ),
    );

    expect(response, isNull);
    final saved = await invoices.getAll();
    expect(saved, hasLength(1));
    expect(saved.single.uuid, 'windows-invoice-for-order');
    expect(
      (await invoices.getItems(saved.single.id!)).single.uuid,
      'windows-invoice-for-order-item',
    );
  });

  test('same bill UUID returns the complete Windows bill graph', () async {
    final windowsBill = makeBill(
      uuid: 'windows-canonical-bill',
      orderUuid: 'financial-sync-order-1',
      number: 'BILL-000012',
      notes: 'Windows bill is canonical',
    );
    await saveWindowsBill(
      windowsBill,
      makeBillItem('windows-canonical-bill-item'),
    );
    final saved = (await bills.getAll()).single;

    final androidBill = windowsBill.copyWith(
      orderUuid: 'unknown-order',
      billNumber: 'BILL-999999',
      notes: 'Android attempted edit',
    );
    final response = await client.sendBill(
      SyncBill(
        bill: androidBill,
        items: [makeBillItem('android-replacement-bill-item')],
      ),
    );

    expect(response, isNotNull);
    expect(response!['bill_number'], 'BILL-000012');
    expect(response['notes'], 'Windows bill is canonical');
    expect(
      (response['items'] as List).single['uuid'],
      'windows-canonical-bill-item',
    );

    final persisted = (await bills.getAll()).single;
    expect(persisted.id, saved.id);
    expect(persisted.billNumber, 'BILL-000012');
    expect(persisted.notes, 'Windows bill is canonical');
    expect(
      (await bills.getItems(persisted.id!)).single.uuid,
      'windows-canonical-bill-item',
    );
  });

  test('bill collisions suffix timestamp-style numbers consistently', () async {
    const base = 'BILL-20261113-103011000042';
    await saveWindowsBill(
      makeBill(
        uuid: 'windows-bill-base',
        orderUuid: 'financial-sync-order-1',
        number: base,
      ),
      makeBillItem('windows-bill-base-item'),
    );

    final incomingA = makeBill(
      uuid: 'android-bill-a',
      orderUuid: 'financial-sync-order-2',
      number: base,
    );
    final itemA = makeBillItem('android-bill-a-item');
    final responseA = await client.sendBill(
      SyncBill(bill: incomingA, items: [itemA]),
    );
    expect(responseA, isNotNull);
    expect(responseA!['bill_number'], base + 'A');

    final retryA = await client.sendBill(
      SyncBill(
        bill: incomingA.copyWith(notes: 'Changed retry payload'),
        items: [makeBillItem('android-bill-a-retry-item')],
      ),
    );
    expect(retryA, isNotNull);
    expect(retryA!['bill_number'], base + 'A');
    expect(retryA['notes'], 'Bill notes');
    expect(
      (retryA['items'] as List).single['uuid'],
      'android-bill-a-item',
    );

    final responseB = await client.sendBill(
      SyncBill(
        bill: makeBill(
          uuid: 'android-bill-b',
          orderUuid: 'financial-sync-order-3',
          number: base,
        ),
        items: [makeBillItem('android-bill-b-item')],
      ),
    );
    expect(responseB, isNotNull);
    expect(responseB!['bill_number'], base + 'B');

    final saved = await bills.getAll();
    expect(saved, hasLength(3));
    expect(
      saved.map((bill) => bill.billNumber).toSet(),
      {base, base + 'A', base + 'B'},
    );
    expect(
      (await bills.getItems(
        saved.singleWhere((bill) => bill.uuid == incomingA.uuid).id!,
      ))
          .single
          .uuid,
      'android-bill-a-item',
    );
  });

  test('a different bill UUID cannot replace the bill for an order', () async {
    await saveWindowsBill(
      makeBill(
        uuid: 'windows-bill-for-order',
        orderUuid: 'financial-sync-order-1',
        number: 'BILL-000040',
      ),
      makeBillItem('windows-bill-for-order-item'),
    );

    final response = await client.sendBill(
      SyncBill(
        bill: makeBill(
          uuid: 'second-bill-same-order',
          orderUuid: 'financial-sync-order-1',
          number: 'BILL-000041',
        ),
        items: [makeBillItem('second-bill-same-order-item')],
      ),
    );

    expect(response, isNull);
    final saved = await bills.getAll();
    expect(saved, hasLength(1));
    expect(saved.single.uuid, 'windows-bill-for-order');
    expect(
      (await bills.getItems(saved.single.id!)).single.uuid,
      'windows-bill-for-order-item',
    );
  });

  test('concurrent invoice number collisions receive different suffixes',
      () async {
    const base = 'INV-000088';
    await saveWindowsInvoice(
      makeInvoice(
        uuid: 'windows-concurrent-invoice',
        orderUuid: 'financial-sync-order-1',
        number: base,
      ),
      makeInvoiceItem('windows-concurrent-invoice-item'),
    );

    final responses = await Future.wait([
      client.sendInvoice(
        SyncInvoice(
          invoice: makeInvoice(
            uuid: 'android-concurrent-invoice-a',
            orderUuid: 'financial-sync-order-2',
            number: base,
          ),
          items: [makeInvoiceItem('android-concurrent-invoice-item-a')],
        ),
      ),
      client.sendInvoice(
        SyncInvoice(
          invoice: makeInvoice(
            uuid: 'android-concurrent-invoice-b',
            orderUuid: 'financial-sync-order-3',
            number: base,
          ),
          items: [makeInvoiceItem('android-concurrent-invoice-item-b')],
        ),
      ),
    ]);

    expect(responses.every((response) => response != null), isTrue);
    expect(
      responses.map((response) => response!['invoice_number']).toSet(),
      {'INV-000088A', 'INV-000088B'},
    );
    expect(await invoices.getAll(), hasLength(3));
  });

  test('concurrent bill number collisions receive different suffixes',
      () async {
    const base = 'BILL-000088';
    await saveWindowsBill(
      makeBill(
        uuid: 'windows-concurrent-bill',
        orderUuid: 'financial-sync-order-1',
        number: base,
      ),
      makeBillItem('windows-concurrent-bill-item'),
    );

    final responses = await Future.wait([
      client.sendBill(
        SyncBill(
          bill: makeBill(
            uuid: 'android-concurrent-bill-a',
            orderUuid: 'financial-sync-order-2',
            number: base,
          ),
          items: [makeBillItem('android-concurrent-bill-item-a')],
        ),
      ),
      client.sendBill(
        SyncBill(
          bill: makeBill(
            uuid: 'android-concurrent-bill-b',
            orderUuid: 'financial-sync-order-3',
            number: base,
          ),
          items: [makeBillItem('android-concurrent-bill-item-b')],
        ),
      ),
    ]);

    expect(responses.every((response) => response != null), isTrue);
    expect(
      responses.map((response) => response!['bill_number']).toSet(),
      {'BILL-000088A', 'BILL-000088B'},
    );
    expect(await bills.getAll(), hasLength(3));
  });
}
