import '../../features/billing/repositories/bill_repository.dart';
import '../../features/customers/repositories/customer_repository.dart';
import '../../features/expenses/models/expense.dart';
import '../../features/expenses/repositories/expense_repository.dart';
import '../../features/invoices/repositories/invoice_repository.dart';
import '../../features/inventory/repositories/asset_repository.dart';
import '../../features/inventory/repositories/consumable_repository.dart';
import '../../features/inventory/repositories/maintenance_repository.dart';
import '../../features/orders/repositories/order_repository.dart';
import '../../features/staff/repositories/staff_repository.dart';
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
  final int assetsPushed;
  final int assetsPulled;
  final int inventoryPushed;
  final int inventoryPulled;
  final int maintenancePushed;
  final int maintenancePulled;
  final int staffRecordsPushed;
  final int staffRecordsPulled;
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
    this.assetsPushed = 0,
    this.assetsPulled = 0,
    this.inventoryPushed = 0,
    this.inventoryPulled = 0,
    this.maintenancePushed = 0,
    this.maintenancePulled = 0,
    this.staffRecordsPushed = 0,
    this.staffRecordsPulled = 0,
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
      ordersPulled +
      assetsPushed +
      assetsPulled +
      inventoryPushed +
      inventoryPulled +
      maintenancePushed +
      maintenancePulled +
      staffRecordsPushed +
      staffRecordsPulled;

  @override
  String toString() {
    if (!connected) return 'Server not reachable';
    return 'Customers: $customersPushed sent, $customersPulled received · '
        'Assets: $assetsPushed sent, $assetsPulled received · '
        'Inventory: $inventoryPushed sent, $inventoryPulled received · '
        'Maintenance: $maintenancePushed sent, $maintenancePulled received · '
        'Staff: $staffRecordsPushed sent, $staffRecordsPulled received · '
        'Bills: $billsPushed sent, $billsPulled received · '
        'Invoices: $invoicesPushed sent, $invoicesPulled received · '
        'Expenses: $expensesPushed sent, $expensesPulled received · '
        'Orders: $ordersPushed sent, $ordersPulled received';
  }
}

/// Two-way LAN sync between an Android client and the Windows host
/// (the source of truth).
///
/// Pending records are pushed first, then the Windows dataset is pulled.
/// Assets, maintenance records and consumable inventory use UUID-addressed
/// relationships; local integer IDs are resolved independently on each device.
/// Windows is authoritative when reconciling these records after the push attempt.
///
/// Conflict rules are entity-specific. For bills, the earliest-created bill
/// for an order wins regardless of sync status; UUID order breaks timestamp ties.
/// Other repositories retain their existing pending-local/Windows rules.
class SyncManager {
  final SyncClient _client;
  final CustomerRepository _customerRepository;
  final BillRepository _billRepository;
  final ExpenseRepository _expenseRepository;
  final InvoiceRepository _invoiceRepository;
  final OrderRepository _orderRepository;
  final AssetRepository _assetRepository;
  final ConsumableRepository _consumableRepository;
  final MaintenanceRepository _maintenanceRepository;
  final StaffRepository _staffRepository;
  final Future<void> Function(DateTime) _saveLastSyncTime;

  Future<SyncResult>? _activeSync;

  SyncManager({
    required this._client,
    CustomerRepository? customerRepository,
    BillRepository? billRepository,
    ExpenseRepository? expenseRepository,
    InvoiceRepository? invoiceRepository,
    OrderRepository? orderRepository,
    AssetRepository? assetRepository,
    ConsumableRepository? consumableRepository,
    MaintenanceRepository? maintenanceRepository,
    StaffRepository? staffRepository,
    Future<void> Function(DateTime)? saveLastSyncTime,
  }) : _customerRepository = customerRepository ?? CustomerRepository(),
       _billRepository = billRepository ?? BillRepository(),
       _expenseRepository = expenseRepository ?? ExpenseRepository(),
       _invoiceRepository = invoiceRepository ?? InvoiceRepository(),
       _orderRepository = orderRepository ?? OrderRepository(),
       _assetRepository = assetRepository ?? AssetRepository(),
       _consumableRepository = consumableRepository ?? ConsumableRepository(),
       _maintenanceRepository = maintenanceRepository ?? MaintenanceRepository(),
       _staffRepository = staffRepository ?? StaffRepository(),
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

  /// Runs at most one sync at a time.
  ///
  /// Concurrent callers share the active sync Future rather than starting
  /// another sync operation against the same local database and server.
  Future<SyncResult> sync() {
    final activeSync = _activeSync;
    if (activeSync != null) return activeSync;

    final syncFuture = _runSync();
    _activeSync = syncFuture;
    return syncFuture;
  }

  Future<SyncResult> _runSync() async {
    try {
      return await _syncInternal();
    } finally {
      _activeSync = null;
    }
  }

  Future<SyncResult> _syncInternal() async {
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
    var assetsPushed = 0;
    var assetsPulled = 0;
    var inventoryPushed = 0;
    var inventoryPulled = 0;
    var maintenancePushed = 0;
    var maintenancePulled = 0;
    var staffRecordsPushed = 0;
    var staffRecordsPulled = 0;

    final acknowledgedCustomers = <String>[];
    final acknowledgedOrders = <String>[];
    final acknowledgedInvoices = <String>[];
    final acknowledgedBills = <String>[];
    final acknowledgedExpenses = <String>[];
    final acknowledgedAssets = <String>[];
    final acknowledgedMaintenance = <String>[];
    final acknowledgedInventory = <Map<String, Object?>>[];
    final acknowledgedStaff = <String>[];
    final acknowledgedStaffAttendance = <String>[];
    final acknowledgedStaffPayments = <String>[];

    // --- Push and pull staff profiles before their dependent records ---
    for (final staff in await _staffRepository.getPendingStaff()) {
      if (await _client.sendStaffRecord('staff', staff.toMap())) {
        await _staffRepository.markSynced('staff', staff.uuid);
        staffRecordsPushed++;
      }
    }
    for (final record in await _client.fetchStaffRecords('staff')) {
      final applied = await _staffRepository.upsertStaffFromSync(record, force: true);
      if (applied) {
        staffRecordsPulled++;
        acknowledgedStaff.add(record['uuid'] as String);
      }
    }

    // --- Push pending assets ---
    for (final asset in await _assetRepository.getPending()) {
      if (await _client.sendAsset(asset)) {
        if (asset.syncStatus == 'deleted_pending') {
          await _assetRepository.finalizeDeletion(asset.uuid);
        } else {
          await _assetRepository.markSynced(asset.uuid);
        }
        assetsPushed++;
      }
    }

    // --- Pull Windows assets; Windows is authoritative after the push attempt ---
    for (final asset in await _client.fetchAssets()) {
      if (asset.syncStatus == 'deleted_pending') {
        await _assetRepository.applyDeletionFromSync(asset.uuid);
        assetsPulled++;
        acknowledgedAssets.add(asset.uuid);
        continue;
      }
      final applied = await _assetRepository.upsertFromSync(asset, force: true);
      if (applied) {
        assetsPulled++;
        acknowledgedAssets.add(asset.uuid);
      }
    }
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

    // Orders are the core sync graph. Reconcile the latest 100-order window by UUID
    // before syncing invoices and bills, which depend on the order identity.
    final localCustomers = await _customerRepository.getAll();
    final customerUuidsById = {
      for (final customer in localCustomers) customer.id!: customer.uuid,
    };
    final customerIdsByUuid = {
      for (final customer in localCustomers) customer.uuid: customer.id!,
    };

    final recentLocalOrders = await _orderRepository.getRecent(limit: 100);
    for (final order in recentLocalOrders) {
      if (order.syncStatus != 'pending') continue;

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

    // Pull the canonical latest 100-order Windows window after pushing local changes.
    // UUID is the identity; order number is only a reconciled attribute.
    for (final syncOrder in await _client.fetchOrders(
      customerIdsByUuid: customerIdsByUuid,
      limit: 100,
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

    // --- Push pending maintenance records after their assets ---
    for (final record in await _maintenanceRepository.getPendingForSync()) {
      if (await _client.sendMaintenanceRecord(record)) {
        if (record['sync_status'] == 'deleted_pending') {
          await _maintenanceRepository.finalizeDeletion(record['uuid'] as String);
        } else {
          await _maintenanceRepository.markSynced(record['uuid'] as String);
        }
        maintenancePushed++;
      }
    }

    // --- Pull Windows maintenance records after assets ---
    for (final record in await _client.fetchMaintenanceRecords()) {
      if (record['sync_status'] == 'deleted_pending') {
        await _maintenanceRepository.applyDeletionFromSync(record['uuid'] as String);
        maintenancePulled++;
        acknowledgedMaintenance.add(record['uuid'] as String);
        continue;
      }
      final applied = await _maintenanceRepository.upsertFromSync(record, force: true);
      if (applied) {
        maintenancePulled++;
        acknowledgedMaintenance.add(record['uuid'] as String);
      }
    }
    // --- Push pending consumables, spools, then activity events ---
    for (final record in await _consumableRepository.getPendingSyncRecords()) {
      if (await _client.sendInventoryRecord(record)) {
        await _consumableRepository.markSyncRecordSynced(
          record['record_type'] as String,
          record['uuid'] as String,
        );
        inventoryPushed++;
      }
    }

    // --- Pull Windows inventory snapshot in dependency order ---
    for (final record in await _client.fetchInventoryRecords()) {
      final applied = await _consumableRepository.upsertSyncRecord(record, force: true);
      if (applied) {
        inventoryPulled++;
        acknowledgedInventory.add({
          'record_type': record['record_type'],
          'uuid': record['uuid'],
        });
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
        if (expense.syncStatus == Expense.syncStatusDeletedPending) {
          await _expenseRepository.finalizeDeletion(expense.uuid);
        } else {
          await _expenseRepository.markSynced(expense.uuid);
        }
        expensesPushed++;
      }
    }

    // --- Pull expenses ---
    for (final expense in await _client.fetchExpenses()) {
      if (expense.syncStatus == Expense.syncStatusDeletedPending) {
        await _expenseRepository.applyDeletionFromSync(expense.uuid);
        expensesPulled++;
        acknowledgedExpenses.add(expense.uuid);
        continue;
      }

      final applied = await _expenseRepository.upsertFromSync(expense);
      if (applied) {
        expensesPulled++;
        acknowledgedExpenses.add(expense.uuid);
      }
    }

    // --- Staff attendance and payments depend on staff profiles ---
    for (final attendance in await _staffRepository.getPendingAttendance()) {
      if (await _client.sendStaffRecord('staff_attendance', attendance.toMap())) {
        await _staffRepository.markSynced('staff_attendance', attendance.uuid);
        staffRecordsPushed++;
      }
    }
    for (final record in await _client.fetchStaffRecords('staff_attendance')) {
      final applied = await _staffRepository.upsertAttendanceFromSync(record, force: true);
      if (applied) {
        staffRecordsPulled++;
        acknowledgedStaffAttendance.add(record['uuid'] as String);
      }
    }

    for (final payment in await _staffRepository.getPendingPayments()) {
      if (await _client.sendStaffRecord('staff_payments', payment.toMap())) {
        await _staffRepository.markSynced('staff_payments', payment.uuid);
        staffRecordsPushed++;
      }
    }
    for (final record in await _client.fetchStaffRecords('staff_payments')) {
      final applied = await _staffRepository.upsertPaymentFromSync(record, force: true);
      if (applied) {
        staffRecordsPulled++;
        acknowledgedStaffPayments.add(record['uuid'] as String);
      }
    }

    if (acknowledgedCustomers.isNotEmpty ||
        acknowledgedOrders.isNotEmpty ||
        acknowledgedInvoices.isNotEmpty ||
        acknowledgedBills.isNotEmpty ||
        acknowledgedExpenses.isNotEmpty ||
        acknowledgedAssets.isNotEmpty ||
        acknowledgedMaintenance.isNotEmpty ||
        acknowledgedInventory.isNotEmpty ||
        acknowledgedStaff.isNotEmpty ||
        acknowledgedStaffAttendance.isNotEmpty ||
        acknowledgedStaffPayments.isNotEmpty) {
      final acknowledged = await _client.acknowledgePulled(
        customerUuids: acknowledgedCustomers,
        orderUuids: acknowledgedOrders,
        invoiceUuids: acknowledgedInvoices,
        billUuids: acknowledgedBills,
        expenseUuids: acknowledgedExpenses,
        assetUuids: acknowledgedAssets,
        maintenanceUuids: acknowledgedMaintenance,
        inventoryRecords: acknowledgedInventory,
        staffUuids: acknowledgedStaff,
        staffAttendanceUuids: acknowledgedStaffAttendance,
        staffPaymentUuids: acknowledgedStaffPayments,
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
      assetsPushed: assetsPushed,
      assetsPulled: assetsPulled,
      inventoryPushed: inventoryPushed,
      inventoryPulled: inventoryPulled,
      maintenancePushed: maintenancePushed,
      maintenancePulled: maintenancePulled,
      staffRecordsPushed: staffRecordsPushed,
      staffRecordsPulled: staffRecordsPulled,
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

    // Pull the complete Windows dataset first. Nothing on the Android
    // database is touched until every dataset has been downloaded.
    final customers = await _client.fetchCustomers();
    final orders = await _client.fetchOrders();
    final invoices = await _client.fetchInvoices();
    final bills = await _client.fetchBills();
    final expenses = await _client.fetchExpenses();
    final assets = await _client.fetchAssets();
    final inventoryRecords = await _client.fetchInventoryRecords();
    final maintenanceRecords = await _client.fetchMaintenanceRecords();
    final staffRecords = await _client.fetchStaffRecords('staff');
    final staffAttendanceRecords = await _client.fetchStaffRecords('staff_attendance');
    final staffPaymentRecords = await _client.fetchStaffRecords('staff_payments');

    // Windows is authoritative for this operation. Replace every local
    // record, including unsynced local changes.
    await _billRepository.deleteAll();
    await _invoiceRepository.deleteAll();
    await _orderRepository.deleteAll();
    await _customerRepository.deleteAll();
    await _expenseRepository.deleteAll();
    await _consumableRepository.deleteAllForSyncReplacement();
    await _maintenanceRepository.deleteAll();
    await _assetRepository.deleteAll();
    await _staffRepository.deleteAllForSyncReplacement();

    for (final customer in customers) {
      await _customerRepository.upsertFromSync(
        customer,
        force: true,
      );
    }

    for (final syncOrder in orders) {
      await _orderRepository.upsertFromSync(
        syncOrder.order,
        syncOrder.items,
        customerUuid: syncOrder.customerUuid,
        force: true,
      );
    }

    for (final syncInvoice in invoices) {
      await _invoiceRepository.upsertFromSync(
        syncInvoice.invoice,
        syncInvoice.items,
        force: true,
      );
    }

    for (final syncBill in bills) {
      await _billRepository.upsertFromSync(
        syncBill.bill,
        syncBill.items,
        force: true,
      );
    }

    final acknowledgedExpenses = <String>[];
    final acknowledgedAssets = <String>[];
    final acknowledgedMaintenance = <String>[];
    final acknowledgedStaff = staffRecords.map((r) => r['uuid'] as String).toList();
    final acknowledgedStaffAttendance = staffAttendanceRecords.map((r) => r['uuid'] as String).toList();
    final acknowledgedStaffPayments = staffPaymentRecords.map((r) => r['uuid'] as String).toList();

    var expensesApplied = 0;

    for (final expense in expenses) {
      if (expense.syncStatus == Expense.syncStatusDeletedPending) {
        acknowledgedExpenses.add(expense.uuid);
        continue;
      }

      await _expenseRepository.upsertFromSync(
        expense,
        force: true,
      );
      expensesApplied++;
    }

    for (final asset in assets) {
      if (asset.syncStatus == 'deleted_pending') {
        acknowledgedAssets.add(asset.uuid);
        continue;
      }
      await _assetRepository.upsertFromSync(asset, force: true);
      acknowledgedAssets.add(asset.uuid);
    }

    final acknowledgedInventory = <Map<String, Object?>>[];
    for (final record in inventoryRecords) {
      await _consumableRepository.upsertSyncRecord(record, force: true);
      acknowledgedInventory.add({
        'record_type': record['record_type'],
        'uuid': record['uuid'],
      });
    }

    for (final record in staffRecords) {
      await _staffRepository.upsertStaffFromSync(record, force: true);
    }
    for (final record in staffAttendanceRecords) {
      await _staffRepository.upsertAttendanceFromSync(record, force: true);
    }
    for (final record in staffPaymentRecords) {
      await _staffRepository.upsertPaymentFromSync(record, force: true);
    }

    for (final record in maintenanceRecords) {
      final uuid = record['uuid'] as String;
      if (record['sync_status'] == 'deleted_pending') {
        acknowledgedMaintenance.add(uuid);
        continue;
      }
      await _maintenanceRepository.upsertFromSync(record, force: true);
      acknowledgedMaintenance.add(uuid);
    }

    // Windows tombstones are temporary. Once the replacement has completed,
    // acknowledge them so Windows can physically remove them as well.
    if (acknowledgedExpenses.isNotEmpty ||
        acknowledgedAssets.isNotEmpty ||
        acknowledgedMaintenance.isNotEmpty ||
        acknowledgedInventory.isNotEmpty ||
        acknowledgedStaff.isNotEmpty ||
        acknowledgedStaffAttendance.isNotEmpty ||
        acknowledgedStaffPayments.isNotEmpty) {
      final acknowledged = await _client.acknowledgePulled(
        customerUuids: const [],
        orderUuids: const [],
        invoiceUuids: const [],
        billUuids: const [],
        expenseUuids: acknowledgedExpenses,
        assetUuids: acknowledgedAssets,
        maintenanceUuids: acknowledgedMaintenance,
        inventoryRecords: acknowledgedInventory,
        staffUuids: acknowledgedStaff,
        staffAttendanceUuids: acknowledgedStaffAttendance,
        staffPaymentUuids: acknowledgedStaffPayments,
      );
      if (!acknowledged) {
        throw StateError(
          'Windows database was pulled, but deletions could not be acknowledged.',
        );
      }
    }

    final result = SyncResult(
      connected: true,
      customersPulled: customers.length,
      billsPulled: bills.length,
      invoicesPulled: invoices.length,
      expensesPulled: expensesApplied,
      ordersPulled: orders.length,
      assetsPulled: assets.where((asset) => asset.syncStatus != 'deleted_pending').length,
      inventoryPulled: inventoryRecords.length,
      maintenancePulled: maintenanceRecords.where((record) => record['sync_status'] != 'deleted_pending').length,
      staffRecordsPulled: staffRecords.length + staffAttendanceRecords.length + staffPaymentRecords.length,
      syncedAt: DateTime.now(),
    );

    await _saveLastSyncTime(result.syncedAt);

    return result;
  }
}
