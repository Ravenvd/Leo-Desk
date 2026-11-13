import 'package:flutter_test/flutter_test.dart';
import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/core/sync/sync_client.dart';
import 'package:leo_desk/core/sync/sync_config.dart';
import 'package:leo_desk/core/sync/sync_server.dart';
import 'package:leo_desk/features/billing/repositories/bill_repository.dart';
import 'package:leo_desk/features/customers/models/customer.dart';
import 'package:leo_desk/features/customers/repositories/customer_repository.dart';
import 'package:leo_desk/features/expenses/repositories/expense_repository.dart';
import 'package:leo_desk/features/invoices/repositories/invoice_repository.dart';
import 'package:leo_desk/features/inventory/repositories/asset_repository.dart';
import 'package:leo_desk/features/inventory/repositories/consumable_repository.dart';
import 'package:leo_desk/features/inventory/repositories/maintenance_repository.dart';
import 'package:leo_desk/features/orders/models/order.dart';
import 'package:leo_desk/features/orders/models/order_item.dart';
import 'package:leo_desk/features/orders/repositories/order_repository.dart';
import 'package:leo_desk/features/staff/repositories/staff_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database database;
  late CustomerRepository customers;
  late OrderRepository orders;
  late SyncServer server;
  late SyncClient client;
  late Customer customer;

  final now = DateTime.utc(2026, 11, 1);

  Order makeOrder({
    required String uuid,
    required String number,
    String status = 'New',
    String? notes,
  }) {
    return Order(
      uuid: uuid,
      orderNumber: number,
      customerId: customer.id!,
      orderDate: now,
      expectedDeliveryDate: now.add(const Duration(days: 5)),
      stitchingRequired: true,
      status: status,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
  }

  OrderItem makeItem(String uuid, {int orderId = 0}) {
    return OrderItem(
      uuid: uuid,
      orderId: orderId,
      workType: 'Embroidery',
      garmentType: 'Blouse',
      quantity: 1,
      unitPricePaise: 25000,
      createdAt: now,
      updatedAt: now,
    );
  }

  setUp(() async {
    database = await AppDatabase.openTestDatabase();
    customers = CustomerRepository(database: database);
    orders = OrderRepository(database: database);
    customer = Customer(
      uuid: 'windows-order-reconcile-customer',
      syncStatus: 'synced',
      name: 'Sync Test Customer',
      createdAt: now,
      updatedAt: now,
    );
    await customers.insert(customer);
    await customers.markSynced(customer.uuid);
    customer = (await customers.getAll()).single;

    server = SyncServer(
      customerRepository: customers,
      billRepository: BillRepository(database: database),
      expenseRepository: ExpenseRepository(database: database),
      invoiceRepository: InvoiceRepository(database: database),
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

  SyncOrder wireOrder(Order order, List<OrderItem> items) => SyncOrder(
        order: order,
        items: items,
        customerUuid: customer.uuid,
      );

  test('same UUID returns the complete Windows record unchanged', () async {
    final windowsOrder = makeOrder(
      uuid: 'windows-canonical-order',
      number: 'ORD-000039',
      status: 'Ready',
      notes: 'Windows is canonical',
    );
    await orders.insert(windowsOrder);
    await orders.markSynced(windowsOrder.uuid);
    final windowsItem = makeItem('windows-canonical-item');
    final saved = (await orders.getAll()).single;
    await database.insert(
      'order_items',
      windowsItem.copyWith(orderId: saved.id!).toMap()..remove('id'),
    );

    final androidVersion = makeOrder(
      uuid: windowsOrder.uuid,
      number: 'ORD-000777',
      status: 'Cancelled',
      notes: 'Android attempted edit',
    );
    final response = await client.sendOrder(
      wireOrder(androidVersion, [makeItem('android-replacement-item')]),
    );

    expect(response, isNotNull);
    expect(response!['order_number'], 'ORD-000039');
    expect(response['status'], 'Ready');
    expect(response['notes'], 'Windows is canonical');
    expect((response['items'] as List).single['uuid'], windowsItem.uuid);

    final persisted = (await orders.getAll()).single;
    expect(persisted.orderNumber, 'ORD-000039');
    expect(persisted.status, 'Ready');
    expect(persisted.notes, 'Windows is canonical');
    expect((await orders.getItems(persisted.id!)).single.uuid, windowsItem.uuid);
  });

  test('distinct UUID collisions receive stable suffixes and preserve both graphs', () async {
    final windowsOrder = makeOrder(
      uuid: 'windows-order-39',
      number: 'ORD-000039',
    );
    await orders.insert(windowsOrder);
    await orders.markSynced(windowsOrder.uuid);
    final windowsSaved = (await orders.getAll()).single;
    final windowsItem = makeItem('windows-order-39-item');
    await database.insert(
      'order_items',
      windowsItem.copyWith(orderId: windowsSaved.id!).toMap()..remove('id'),
    );

    final androidOrderA = makeOrder(
      uuid: 'android-order-39-a',
      number: 'ORD-000039',
      notes: 'Offline A',
    );
    final itemA = makeItem('android-order-39-a-item');
    final responseA = await client.sendOrder(wireOrder(androidOrderA, [itemA]));
    expect(responseA, isNotNull);
    expect(responseA!['order_number'], 'ORD-000039A');

    final responseRetry = await client.sendOrder(wireOrder(androidOrderA, [itemA]));
    expect(responseRetry, isNotNull);
    expect(responseRetry!['order_number'], 'ORD-000039A');

    final androidOrderB = makeOrder(
      uuid: 'android-order-39-b',
      number: 'ORD-000039',
      notes: 'Offline B',
    );
    final responseB = await client.sendOrder(
      wireOrder(androidOrderB, [makeItem('android-order-39-b-item')]),
    );
    expect(responseB, isNotNull);
    expect(responseB!['order_number'], 'ORD-000039B');

    final persisted = await orders.getAll();
    expect(persisted, hasLength(3));
    expect(
      persisted.map((order) => order.orderNumber).toSet(),
      {'ORD-000039', 'ORD-000039A', 'ORD-000039B'},
    );

    final canonicalWindows = persisted.singleWhere(
      (order) => order.uuid == windowsOrder.uuid,
    );
    final canonicalA = persisted.singleWhere(
      (order) => order.uuid == androidOrderA.uuid,
    );
    expect(
      (await orders.getItems(canonicalWindows.id!)).single.uuid,
      windowsItem.uuid,
    );
    expect(
      (await orders.getItems(canonicalA.id!)).single.uuid,
      itemA.uuid,
    );
  });

  test('concurrent distinct UUID collisions receive different suffixes', () async {
    final windowsOrder = makeOrder(
      uuid: 'windows-concurrent-base',
      number: 'ORD-000088',
    );
    await orders.insert(windowsOrder);
    await orders.markSynced(windowsOrder.uuid);

    final androidA = makeOrder(
      uuid: 'android-concurrent-a',
      number: 'ORD-000088',
    );
    final androidB = makeOrder(
      uuid: 'android-concurrent-b',
      number: 'ORD-000088',
    );

    final responses = await Future.wait([
      client.sendOrder(wireOrder(androidA, [makeItem('android-concurrent-item-a')])),
      client.sendOrder(wireOrder(androidB, [makeItem('android-concurrent-item-b')])),
    ]);

    expect(responses.every((response) => response != null), isTrue);
    final assigned = responses
        .map((response) => response!['order_number'] as String)
        .toSet();
    expect(assigned, {'ORD-000088A', 'ORD-000088B'});
    expect(await orders.getAll(), hasLength(3));
  });
}
