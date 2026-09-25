import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/core/sync/sync_client.dart';
import 'package:leo_desk/core/sync/sync_manager.dart';
import 'package:leo_desk/core/sync/sync_server.dart';
import 'package:leo_desk/features/billing/repositories/bill_repository.dart';
import 'package:leo_desk/features/customers/models/customer.dart';
import 'package:leo_desk/features/customers/repositories/customer_repository.dart';
import 'package:leo_desk/features/expenses/repositories/expense_repository.dart';
import 'package:leo_desk/features/invoices/models/invoice.dart';
import 'package:leo_desk/features/invoices/models/invoice_item.dart';
import 'package:leo_desk/features/invoices/repositories/invoice_repository.dart';
import 'package:leo_desk/features/orders/models/order.dart';
import 'package:leo_desk/features/orders/repositories/order_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FailingInvoiceSyncClient extends SyncClient {
  bool failInvoice;

  FailingInvoiceSyncClient({
    required super.serverAddress,
    required super.port,
    required this.failInvoice,
  });

  @override
  Future<bool> sendInvoice(SyncInvoice invoice) async {
    if (failInvoice) return false;
    return super.sendInvoice(invoice);
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDirectory;
  late Database serverDatabase;
  late Database clientDatabase;
  late int port;

  setUp(() async {
    testDirectory =
        await Directory.systemTemp.createTemp('leo_desk_sync_partial_test_');

    serverDatabase = await AppDatabase.openTestDatabase(
      path: '${testDirectory.path}${Platform.pathSeparator}server.db',
    );
    clientDatabase = await AppDatabase.openTestDatabase(
      path: '${testDirectory.path}${Platform.pathSeparator}client.db',
    );

    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = socket.port;
    await socket.close();
  });

  tearDown(() async {
    await serverDatabase.close();
    await clientDatabase.close();
    await testDirectory.delete(recursive: true);
  });

  test(
    'keeps failed invoice pending while successful order is not duplicated on retry',
    () async {
      final clientCustomers = CustomerRepository(database: clientDatabase);
      final clientOrders = OrderRepository(database: clientDatabase);
      final clientInvoices = InvoiceRepository(database: clientDatabase);

      final serverCustomers = CustomerRepository(database: serverDatabase);
      final serverOrders = OrderRepository(database: serverDatabase);
      final serverInvoices = InvoiceRepository(database: serverDatabase);

      final now = DateTime.utc(2026, 2, 10, 8);

      final customer = Customer(
        uuid: 'partial-sync-customer',
        name: 'Partial Sync Customer',
        phone: '9999999999',
        createdAt: now,
        updatedAt: now,
      );
      final customerId = await clientCustomers.insert(customer);

      final order = Order(
        uuid: 'partial-sync-order',
        orderNumber: 'LOCAL-001',
        customerId: customerId,
        orderDate: now,
        expectedDeliveryDate: now.add(const Duration(days: 7)),
        stitchingRequired: true,
        stitchingPricePaise: 50000,
        createdAt: now,
        updatedAt: now,
      );
      final orderId = await clientOrders.insert(order);

      final invoice = Invoice(
        uuid: 'partial-sync-invoice',
        orderId: orderId,
        orderUuid: order.uuid,
        customerId: customerId,
        customerUuid: customer.uuid,
        invoiceNumber: 'INV-001',
        invoiceDate: now,
        subtotalPaise: 100000,
        totalPaise: 100000,
        createdAt: now,
        updatedAt: now,
      );
      await clientInvoices.create(
        invoice: invoice,
        items: [
          InvoiceItem(
            invoiceId: 0,
            description: 'Embroidery work',
            quantity: 1,
            ratePaise: 100000,
            amountPaise: 100000,
          ),
        ],
      );

      final client = FailingInvoiceSyncClient(
        serverAddress: '127.0.0.1',
        port: port,
        failInvoice: true,
      );

      final manager = SyncManager(
        client: client,
        customerRepository: clientCustomers,
        orderRepository: clientOrders,
        invoiceRepository: clientInvoices,
        saveLastSyncTime: (_) async {},
      );

      final server = SyncServer(
        customerRepository: serverCustomers,
        billRepository: BillRepository(database: serverDatabase),
        expenseRepository: ExpenseRepository(database: serverDatabase),
        invoiceRepository: serverInvoices,
        orderRepository: serverOrders,
      );
      await server.start(port: port);

      try {
        final firstResult = await manager.sync();

        expect(firstResult.connected, isTrue);
        expect(firstResult.ordersPushed, 1);
        expect(firstResult.invoicesPushed, 0);

        final localOrder = await clientOrders.getById(orderId);
        expect(localOrder, isNotNull);
        expect(localOrder!.syncStatus, 'synced');

        final pendingInvoices = await clientInvoices.getPending();
        expect(
          pendingInvoices.map((item) => item.uuid),
          contains(invoice.uuid),
        );

        expect(
          (await serverOrders.getAll())
              .where((item) => item.uuid == order.uuid)
              .length,
          1,
        );
        expect(
          (await serverInvoices.getAll())
              .where((item) => item.uuid == invoice.uuid)
              .length,
          0,
        );

        client.failInvoice = false;

        final secondResult = await manager.sync();

        expect(secondResult.connected, isTrue);
        expect(secondResult.ordersPushed, 0);
        expect(secondResult.invoicesPushed, 1);

        expect(await clientInvoices.getPending(), isEmpty);

        expect(
          (await serverOrders.getAll())
              .where((item) => item.uuid == order.uuid)
              .length,
          1,
        );
        expect(
          (await serverInvoices.getAll())
              .where((item) => item.uuid == invoice.uuid)
              .length,
          1,
        );
      } finally {
        await server.stop();
      }
    },
  );
}
