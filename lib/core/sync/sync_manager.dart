import '../../features/billing/repositories/bill_repository.dart';
import '../../features/customers/repositories/customer_repository.dart';
import '../../features/expenses/repositories/expense_repository.dart';
import 'sync_client.dart';
import 'sync_config.dart';

class SyncResult {
  final bool connected;
  final int customersPushed;
  final int customersPulled;
  final int billsPushed;
  final int billsPulled;
  final int expensesPushed;
  final int expensesPulled;
  final DateTime syncedAt;

  const SyncResult({
    required this.connected,
    this.customersPushed = 0,
    this.customersPulled = 0,
    this.billsPushed = 0,
    this.billsPulled = 0,
    this.expensesPushed = 0,
    this.expensesPulled = 0,
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
      expensesPushed +
      expensesPulled;

  @override
  String toString() {
    if (!connected) return 'Server not reachable';
    return 'Customers: $customersPushed sent, $customersPulled received · '
        'Bills: $billsPushed sent, $billsPulled received · '
        'Expenses: $expensesPushed sent, $expensesPulled received';
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
  final Future<void> Function(DateTime) _saveLastSyncTime;

  SyncManager({
    required this._client,
    CustomerRepository? customerRepository,
    BillRepository? billRepository,
    ExpenseRepository? expenseRepository,
    Future<void> Function(DateTime)? saveLastSyncTime,
  }) : _customerRepository = customerRepository ?? CustomerRepository(),
       _billRepository = billRepository ?? BillRepository(),
       _expenseRepository = expenseRepository ?? ExpenseRepository(),
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
    var expensesPushed = 0;
    var expensesPulled = 0;

    // --- Push pending customers ---
    for (final customer in await _customerRepository.getPending()) {
      if (await _client.sendCustomer(customer)) {
        await _customerRepository.markSynced(customer.uuid);
        customersPushed++;
      }
    }

    // --- Pull customers (before bills, so bill customer links resolve) ---
    for (final customer in await _client.fetchCustomers()) {
      await _customerRepository.upsertFromSync(customer);
      customersPulled++;
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
      if (applied) billsPulled++;
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
      if (applied) expensesPulled++;
    }

    final result = SyncResult(
      connected: true,
      customersPushed: customersPushed,
      customersPulled: customersPulled,
      billsPushed: billsPushed,
      billsPulled: billsPulled,
      expensesPushed: expensesPushed,
      expensesPulled: expensesPulled,
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
    final bills = await _client.fetchBills();
    final expenses = await _client.fetchExpenses();

    await _billRepository.deleteAll();
    await _customerRepository.deleteAll();
    await _expenseRepository.deleteAll();

    var billsApplied = 0;
    var expensesApplied = 0;

    for (final customer in customers) {
      await _customerRepository.upsertFromSync(customer);
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
      expensesPulled: expensesApplied,
      syncedAt: DateTime.now(),
    );

    await _saveLastSyncTime(result.syncedAt);

    return result;
  }
}
