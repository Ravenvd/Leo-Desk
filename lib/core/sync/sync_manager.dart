import '../../features/billing/repositories/bill_repository.dart';
import '../../features/customers/repositories/customer_repository.dart';
import 'sync_client.dart';
import 'sync_config.dart';

class SyncResult {
  final bool connected;
  final int customersPushed;
  final int customersPulled;
  final int billsPushed;
  final int billsPulled;
  final DateTime syncedAt;

  const SyncResult({
    required this.connected,
    this.customersPushed = 0,
    this.customersPulled = 0,
    this.billsPushed = 0,
    this.billsPulled = 0,
    required this.syncedAt,
  });

  factory SyncResult.notConnected() {
    return SyncResult(connected: false, syncedAt: DateTime.now());
  }

  int get totalSynced =>
      customersPushed + customersPulled + billsPushed + billsPulled;

  @override
  String toString() {
    if (!connected) return 'Server not reachable';
    return 'Customers: $customersPushed sent, $customersPulled received · '
        'Bills: $billsPushed sent, $billsPulled received';
  }
}

/// Two-way LAN sync between an Android client and the Windows host
/// (the source of truth).
///
/// Order of operations:
/// 1. Push locally pending customers and bills to the server.
/// 2. Pull the server's customers and bills and apply them locally.
///
/// Conflict rule (applied in the repositories): a locally pending record
/// always wins over the server copy; otherwise Windows wins.
class SyncManager {
  final SyncClient _client;
  final CustomerRepository _customerRepository;
  final BillRepository _billRepository;

  SyncManager({
    required this._client,
    CustomerRepository? customerRepository,
    BillRepository? billRepository,
  }) : _customerRepository = customerRepository ?? CustomerRepository(),
       _billRepository = billRepository ?? BillRepository();

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

    final result = SyncResult(
      connected: true,
      customersPushed: customersPushed,
      customersPulled: customersPulled,
      billsPushed: billsPushed,
      billsPulled: billsPulled,
      syncedAt: DateTime.now(),
    );

    await SyncConfig.saveLastSyncTime(result.syncedAt);

    return result;
  }
}
