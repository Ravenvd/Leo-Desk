import '../../features/billing/repositories/bill_repository.dart';
import '../../features/customers/repositories/customer_repository.dart';
import '../../features/expenses/repositories/expense_repository.dart';
import '../../features/invoices/repositories/invoice_repository.dart';
import '../../features/orders/repositories/order_repository.dart';
import 'sync_client.dart';
import 'sync_config.dart';

class SyncResult {
  final bool connected;
  final int customersPushed;
  final int customersPulled;
  final int billsPushed;
  final int billsPulled;
  final int invoicesPushed;
  final int invoicesPulled;
  final int expensesPushed;
  final int expensesPulled;
  final int ordersPushed;
  final int ordersPulled;
  final DateTime syncedAt;

  const SyncResult({
    required this.connected,
    this.customersPushed = 0,
    this.customersPulled = 0,
    this.billsPushed = 0,
    this.billsPulled = 0,
    this.invoicesPushed = 0,
    this.invoicesPulled = 0,
    this.expensesPushed = 0,
    this.expensesPulled = 0,
    this.ordersPushed = 0,
    this.ordersPulled = 0,
    required this.syncedAt,
  });

  factory SyncResult.notConnected() {
    return SyncResult(connected: false, syncedAt: DateTime.now());
  }

  int get totalSynced =>
      customersPushed +
      customersPulled +
      billsPushed +
      billsPulled +
      invoicesPushed +
      invoicesPulled +
      expensesPushed +
      expensesPulled +
      ordersPushed +
      ordersPulled;

  @override
  String toString() {
    if (!connected) return 'Server not reachable';
    return 'Customers: $customersPushed sent, $customersPulled received · '
        'Bills: $billsPushed sent, $billsPulled received · '
        'Invoices: $invoicesPushed sent, $invoicesPulled received · '
        'Expenses: $expensesPushed sent, $expensesPulled received · '
        'Orders: $ordersPushed sent, $ordersPulled received';
  }
}

/// Two-way LAN sync between an Android client and the Windows host
/// (the source of truth).
///
/// Order of operations:
/// 1. Push locally pending customers, bills, and expenses to the server.
/// 2. Pull the server's customers, bills, and expenses and apply them locally.
///
/// Conflict rule (applied in the repositories): a locally pending record
/// always wins over the server copy; otherwise Windows wins.
class SyncManager {
  final SyncClient _client;
  final CustomerRepository _customerRepository;
  final BillRepository _billRepository;
  final ExpenseRepository _expenseRepository;
  final InvoiceRepository _invoiceRepository;
  final OrderRepository _orderRepository;
  final Future<void> Function(DateTime) _saveLastSyncTime;

  SyncManager({
    required this._client,
    CustomerRepository? customerRepository,
    BillRepository? billRepository,
    ExpenseRepository? expenseRepository,
    InvoiceRepository? invoiceRepository,
    OrderRepository? orderRepository,
    Future<void> Function(DateTime)? saveLastSyncTime,
  }) : _customerRepository = customerRepository ?? CustomerRepository(),
       _billRepository = billRepository ?? BillRepository(),
       _expenseRepository = expenseRepository ?? ExpenseRepository(),
       _invoiceRepository = invoiceRepository ?? InvoiceRepository(),
       _orderRepository = orderRepository ?? OrderRepository(),
       _saveLastSyncTime = saveLastSyncTime ?? SyncConfig.saveLastSyncTime;

  factory SyncManager.fromConfig(SyncConfig config) {
    return SyncManager(
      client: SyncClient(
        serverAddress: config.serverHost ?? '',
        port: config.serverPort,
        token: config.token,
      ),
    );
  }

  Future<SyncResult> sync() async {
    if (!await _client.checkConnection()) {
      return SyncResult.notConnected();
    }

    var customersPushed = 0;
    var customersPulled = 0;
    var billsPushed = 0;
    var billsPulled = 0;
    var invoicesPushed = 0;
    var invoicesPulled = 0;
    var expensesPushed = 0;
    var expensesPulled = 0;
    var ordersPushed = 0;
    var ordersPulled = 0;

    final acknowledgedCustomers = <String>[];
    final acknowledgedOrders = <String>[];
    final acknowledgedInvoices = <String>[];
    final acknowledgedBills = <String>[];
    final acknowledgedExpenses = <String>[];

    // --- Push pending customers ---
    for (final customer in await _customerRepository.getPending()) {
      if (await _client.sendCustomer(customer)) {
        await _customerRepository.markSynced(customer.uuid);
        customersPushed++;
      }
    }

    // --- Pull customers (before bills, so bill customer links resolve) ---
    for (final customer in await _client.fetchCustomers()) {
      final applied = await _customerRepository.upsertFromSync(customer);
      if (applied) {
        customersPulled++;
        acknowledgedCustomers.add(customer.uuid);
      }
    }

    // Orders must sync before invoices and bills because both reference them.
    // --- Push pending orders ---
    final localCustomers = await _customerRepository.getAll();
    final customerUuidsById = {
      for (final customer in localCustomers) customer.id!: customer.uuid,
    };

    for (final order in await _orderRepository.getPending()) {
      final customerUuid = customerUuidsById[order.customerId];
      if (customerUuid == null) continue;

      final items = await _orderRepository.getItems(order.id!);
      final pushedOrderNumber = await _client.sendOrder(
        SyncOrder(
          order: order,
          items: items,
          customerUuid: customerUuid,
        ),
      );
      if (pushedOrderNumber != null) {
        if (pushedOrderNumber != order.orderNumber) {
          await _orderRepository.updateOrderNumberAndMarkSynced(
            order.uuid,
            pushedOrderNumber,
          );
        } else {
          await _orderRepository.markSynced(order.uuid);
        }
        ordersPushed++;
      }
    }

    // --- Pull orders after customers so foreign keys resolve ---
    final customerIdsByUuid = {
      for (final customer in await _customerRepository.getAll())
        customer.uuid: customer.id!,
    };

    for (final syncOrder in await _client.fetchOrders(
      customerIdsByUuid: customerIdsByUuid,
    )) {
      final applied = await _orderRepository.upsertFromSync(
        syncOrder.order,
        syncOrder.items,
      );
      if (applied) {
        ordersPulled++;
        acknowledgedOrders.add(syncOrder.order.uuid);
      }
    }

    // --- Push pending invoices ---
    for (final invoice in await _invoiceRepository.getPending()) {
      final items = await _invoiceRepository.getItems(invoice.id!);
      if (await _client.sendInvoice(
        SyncInvoice(invoice: invoice, items: items),
      )) {
        await _invoiceRepository.markSynced(invoice.uuid);
        invoicesPushed++;
      }
    }

    // --- Pull invoices ---
    final localOrderIdsByUuid = {
      for (final order in await _orderRepository.getAll()) order.uuid: order.id!,
    };
    for (final syncInvoice in await _client.fetchInvoices(
      customerIdsByUuid: customerIdsByUuid,
      orderIdsByUuid: localOrderIdsByUuid,
    )) {
      final applied = await _invoiceRepository.upsertFromSync(
        syncInvoice.invoice,
        syncInvoice.items,
      );
      if (applied) {
        invoicesPulled++;
        acknowledgedInvoices.add(syncInvoice.invoice.uuid);
      }
    }

    // --- Push pending bills ---
    for (final bill in await _billRepository.getPending()) {
      final items = await _billRepository.getItems(bill.id!);
      if (await _client.sendBill(SyncBill(bill: bill, items: items))) {
        await _billRepository.markSynced(bill.uuid);
        billsPushed++;
      }
    }

    // --- Pull bills ---
    for (final syncBill in await _client.fetchBills()) {
      final applied = await _billRepository.upsertFromSync(
        syncBill.bill,
        syncBill.items,
      );
      if (applied) {
        billsPulled++;
        acknowledgedBills.add(syncBill.bill.uuid);
      }
    }

    // --- Push pending expenses ---
    for (final expense in await _expenseRepository.getPending()) {
      if (await _client.sendExpense(expense)) {
        await _expenseRepository.markSynced(expense.uuid);
        expensesPushed++;
      }
    }

    // --- Pull expenses ---
    for (final expense in await _client.fetchExpenses()) {
      final applied = await _expenseRepository.upsertFromSync(expense);
      if (applied) {
        expensesPulled++;
        acknowledgedExpenses.add(expense.uuid);
      }
    }

    if (acknowledgedCustomers.isNotEmpty ||
        acknowledgedOrders.isNotEmpty ||
        acknowledgedInvoices.isNotEmpty ||
        acknowledgedBills.isNotEmpty ||
        acknowledgedExpenses.isNotEmpty) {
      final acknowledged = await _client.acknowledgePulled(
        customerUuids: acknowledgedCustomers,
        orderUuids: acknowledgedOrders,
        invoiceUuids: acknowledgedInvoices,
        billUuids: acknowledgedBills,
        expenseUuids: acknowledgedExpenses,
      );
      if (!acknowledged) {
        throw StateError(
          'Pulled records were applied, but Windows could not confirm sync.',
        );
      }
    }

    final result = SyncResult(
      connected: true,
      customersPushed: customersPushed,
      customersPulled: customersPulled,
      billsPushed: billsPushed,
      billsPulled: billsPulled,
      invoicesPushed: invoicesPushed,
      invoicesPulled: invoicesPulled,
      expensesPushed: expensesPushed,
      expensesPulled: expensesPulled,
      ordersPushed: ordersPushed,
      ordersPulled: ordersPulled,
      syncedAt: DateTime.now(),
    );

    await _saveLastSyncTime(result.syncedAt);

    return result;
  }

  /// Completely replaces the local database with the server's dataset.
  ///
  /// All local customers, bills, and expenses (including unsynced pending
  /// changes) are discarded, then the Windows host's data is applied.
  /// Everything pulled is marked synced. Windows is the source of truth.
  Future<SyncResult> pullAndReplace() async {
    if (!await _client.checkConnection()) {
      return SyncResult.notConnected();
    }

    final customers = await _client.fetchCustomers();
    final expenses = await _client.fetchExpenses();

    await _billRepository.deleteAll();
    await _invoiceRepository.deleteAll();
    await _orderRepository.deleteAll();
    await _customerRepository.deleteAll();
    await _expenseRepository.deleteAll();

    var billsApplied = 0;
    var invoicesApplied = 0;
    var expensesApplied = 0;
    var ordersApplied = 0;

    for (final customer in customers) {
      await _customerRepository.upsertFromSync(customer);
    }

    final customerIdsByUuid = {
      for (final customer in await _customerRepository.getAll())
        customer.uuid: customer.id!,
    };
    final orders = await _client.fetchOrders(
      customerIdsByUuid: customerIdsByUuid,
    );

    for (final syncOrder in orders) {
      final applied = await _orderRepository.upsertFromSync(
        syncOrder.order,
        syncOrder.items,
      );
      if (applied) ordersApplied++;
    }

    final localOrderIdsByUuid = {
      for (final order in await _orderRepository.getAll()) order.uuid: order.id!,
    };
    final invoices = await _client.fetchInvoices(
      customerIdsByUuid: {
        for (final customer in await _customerRepository.getAll())
          customer.uuid: customer.id!,
      },
      orderIdsByUuid: localOrderIdsByUuid,
    );
    final bills = await _client.fetchBills();

    for (final syncInvoice in invoices) {
      final applied = await _invoiceRepository.upsertFromSync(
        syncInvoice.invoice,
        syncInvoice.items,
      );
      if (applied) invoicesApplied++;
    }

    for (final syncBill in bills) {
      final applied = await _billRepository.upsertFromSync(
        syncBill.bill,
        syncBill.items,
      );
      if (applied) billsApplied++;
    }

    for (final expense in expenses) {
      final applied = await _expenseRepository.upsertFromSync(expense);
      if (applied) expensesApplied++;
    }

    final result = SyncResult(
      connected: true,
      customersPulled: customers.length,
      billsPulled: billsApplied,
      invoicesPulled: invoicesApplied,
      expensesPulled: expensesApplied,
      ordersPulled: ordersApplied,
      syncedAt: DateTime.now(),
    );

    await _saveLastSyncTime(result.syncedAt);

    return result;
  }
}
