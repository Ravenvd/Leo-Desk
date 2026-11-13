import 'dart:convert';
import 'dart:io';

import '../../features/billing/repositories/bill_repository.dart';
import '../../features/customers/models/customer.dart';
import '../../features/customers/repositories/customer_repository.dart';
import '../../features/expenses/models/expense.dart';
import '../../features/expenses/repositories/expense_repository.dart';
import '../../features/invoices/repositories/invoice_repository.dart';
import '../../features/inventory/models/asset.dart';
import '../../features/inventory/repositories/asset_repository.dart';
import '../../features/inventory/repositories/consumable_repository.dart';
import '../../features/inventory/repositories/maintenance_repository.dart';
import '../../features/orders/repositories/order_repository.dart';
import '../../features/staff/repositories/staff_repository.dart';
import 'sync_client.dart';
import 'sync_config.dart';

class SyncServer {
  static const int _maxBodyBytes = 5 * 1024 * 1024;

  HttpServer? _server;

  final CustomerRepository _customerRepository;
  final BillRepository _billRepository;
  final ExpenseRepository _expenseRepository;
  final InvoiceRepository _invoiceRepository;
  final OrderRepository _orderRepository;
  final AssetRepository _assetRepository;
  final ConsumableRepository _consumableRepository;
  final MaintenanceRepository _maintenanceRepository;
  final StaffRepository _staffRepository;
  final String token;

  SyncServer({
    CustomerRepository? customerRepository,
    BillRepository? billRepository,
    ExpenseRepository? expenseRepository,
    InvoiceRepository? invoiceRepository,
    OrderRepository? orderRepository,
    AssetRepository? assetRepository,
    ConsumableRepository? consumableRepository,
    MaintenanceRepository? maintenanceRepository,
    StaffRepository? staffRepository,
    this.token = SyncConfig.defaultToken,
  }) : _customerRepository = customerRepository ?? CustomerRepository(),
       _billRepository = billRepository ?? BillRepository(),
       _expenseRepository = expenseRepository ?? ExpenseRepository(),
       _invoiceRepository = invoiceRepository ?? InvoiceRepository(),
       _orderRepository = orderRepository ?? OrderRepository(),
       _assetRepository = assetRepository ?? AssetRepository(),
       _consumableRepository = consumableRepository ?? ConsumableRepository(),
       _maintenanceRepository = maintenanceRepository ?? MaintenanceRepository(),
       _staffRepository = staffRepository ?? StaffRepository();

  bool get isRunning => _server != null;

  int? get port => _server?.port;

  Future<void> start({int port = SyncConfig.defaultPort}) async {
    if (_server != null) {
      return;
    }

    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);

    _server!.listen(
      _handleRequest,
      onError: (Object error) {
        // Keep serving subsequent requests even if one connection fails.
        // ignore: avoid_print
        print('SyncServer connection error: $error');
      },
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.headers.value('X-Leo-Sync-Token') != token) {
        await _sendJson(request.response, 401, {'error': 'Unauthorized'});
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/api/health') {
        await _sendJson(request.response, 200, {
          'status': 'ok',
          'service': 'leo-desk-sync',
        });
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/api/sync/ack') {
        final decoded = await _readJsonBody(request);
        if (decoded is! Map) {
          await _sendJson(request.response, 400, {
            'error': 'Invalid sync acknowledgement.',
          });
          return;
        }

        List<String> uuids(String key) {
          final value = decoded[key];
          if (value is! List) return <String>[];
          return value.whereType<String>().toList();
        }

        for (final uuid in uuids('customers')) {
          await _customerRepository.markSynced(uuid);
        }
        for (final uuid in uuids('orders')) {
          await _orderRepository.markSynced(uuid);
        }
        for (final uuid in uuids('invoices')) {
          await _invoiceRepository.markSynced(uuid);
        }
        for (final uuid in uuids('bills')) {
          await _billRepository.markSynced(uuid);
        }
        for (final uuid in uuids('expenses')) {
          await _expenseRepository.acknowledgeSyncedOrDeleted(uuid);
        }
        for (final uuid in uuids('assets')) {
          await _assetRepository.acknowledgeSyncedOrDeleted(uuid);
        }
        for (final uuid in uuids('maintenance_records')) {
          await _maintenanceRepository.acknowledgeSyncedOrDeleted(uuid);
        }
        for (final uuid in uuids('staff')) {
          await _staffRepository.markSynced('staff', uuid);
        }
        for (final uuid in uuids('staff_attendance')) {
          await _staffRepository.markSynced('staff_attendance', uuid);
        }
        for (final uuid in uuids('staff_payments')) {
          await _staffRepository.markSynced('staff_payments', uuid);
        }
        final inventoryRecords = decoded['inventory_records'];
        if (inventoryRecords is List) {
          for (final item in inventoryRecords) {
            if (item is! Map) continue;
            final table = item['record_type'];
            final uuid = item['uuid'];
            if (table is String && uuid is String) {
              await _consumableRepository.markSyncRecordSynced(table, uuid);
            }
          }
        }

        await _sendJson(request.response, 200, {
          'status': 'ok',
          'uuid': 'ack',
        });
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/api/staff') {
        final records = await _staffRepository.getAllStaffForSync();
        await _sendJson(request.response, 200, records.map((record) {
          return Map<String, Object?>.from(record)..remove('id');
        }).toList());
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/api/staff') {
        final decoded = await _readJsonBody(request);
        if (decoded is! Map || decoded['uuid'] is! String) {
          await _sendJson(request.response, 400, {'error': 'Invalid staff record.'});
          return;
        }
        final record = Map<String, Object?>.from(decoded);
        final uuid = record['uuid'] as String;
        final applied = await _staffRepository.upsertStaffFromSync(record);
        if (!applied) {
          await _sendJson(request.response, 409, {'error': 'Staff record has a pending Windows edit.', 'uuid': uuid});
          return;
        }
        await _sendJson(request.response, 200, {'status': 'ok', 'uuid': uuid});
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/api/staff/attendance') {
        final records = await _staffRepository.getAllAttendanceForSync();
        await _sendJson(request.response, 200, records.map((record) {
          return Map<String, Object?>.from(record)..remove('id');
        }).toList());
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/api/staff/attendance') {
        final decoded = await _readJsonBody(request);
        if (decoded is! Map || decoded['uuid'] is! String) {
          await _sendJson(request.response, 400, {'error': 'Invalid staff attendance record.'});
          return;
        }
        final record = Map<String, Object?>.from(decoded);
        final uuid = record['uuid'] as String;
        final applied = await _staffRepository.upsertAttendanceFromSync(record);
        if (!applied) {
          await _sendJson(request.response, 409, {'error': 'Staff attendance could not be applied.', 'uuid': uuid});
          return;
        }
        await _sendJson(request.response, 200, {'status': 'ok', 'uuid': uuid});
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/api/staff/payments') {
        final records = await _staffRepository.getAllPaymentsForSync();
        await _sendJson(request.response, 200, records.map((record) {
          return Map<String, Object?>.from(record)..remove('id');
        }).toList());
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/api/staff/payments') {
        final decoded = await _readJsonBody(request);
        if (decoded is! Map || decoded['uuid'] is! String) {
          await _sendJson(request.response, 400, {'error': 'Invalid staff payment record.'});
          return;
        }
        final record = Map<String, Object?>.from(decoded);
        final uuid = record['uuid'] as String;
        final applied = await _staffRepository.upsertPaymentFromSync(record);
        if (!applied) {
          await _sendJson(request.response, 409, {'error': 'Staff payment could not be applied.', 'uuid': uuid});
          return;
        }
        await _sendJson(request.response, 200, {'status': 'ok', 'uuid': uuid});
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/api/maintenance') {
        await _sendJson(request.response, 200, await _maintenanceRepository.getAllForSync());
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/api/maintenance/delete') {
        final decoded = await _readJsonBody(request);
        if (decoded is! Map || decoded['uuid'] is! String) {
          await _sendJson(request.response, 400, {'error': 'Invalid maintenance deletion data.'});
          return;
        }
        final uuid = decoded['uuid'] as String;
        await _maintenanceRepository.markDeletedPendingByUuid(uuid);
        await _sendJson(request.response, 200, {'status': 'ok', 'uuid': uuid});
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/api/maintenance') {
        final decoded = await _readJsonBody(request);
        if (decoded is! Map || decoded['uuid'] is! String) {
          await _sendJson(request.response, 400, {'error': 'Invalid maintenance record.'});
          return;
        }
        final record = Map<String, Object?>.from(decoded);
        final uuid = record['uuid'] as String;
        final applied = await _maintenanceRepository.upsertFromSync(record);
        if (!applied) {
          await _sendJson(request.response, 409, {'error': 'Maintenance record has a pending Windows edit.', 'uuid': uuid});
          return;
        }
        await _sendJson(request.response, 200, {'status': 'ok', 'uuid': uuid});
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/api/inventory') {
        final records = await _consumableRepository.getAllSyncRecords();
        await _sendJson(request.response, 200, records);
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/api/inventory') {
        final decoded = await _readJsonBody(request);
        if (decoded is! Map) {
          await _sendJson(request.response, 400, {'error': 'Invalid inventory record.'});
          return;
        }
        final record = Map<String, Object?>.from(decoded);
        final uuid = record['uuid'];
        if (uuid is! String) {
          await _sendJson(request.response, 400, {'error': 'Inventory UUID is required.'});
          return;
        }
        final applied = await _consumableRepository.upsertSyncRecord(record);
        if (!applied) {
          await _sendJson(request.response, 409, {'error': 'Inventory record has a pending Windows edit.', 'uuid': uuid});
          return;
        }
        await _sendJson(request.response, 200, {'status': 'ok', 'uuid': uuid});
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/api/assets') {
        final assets = await _assetRepository.getAllForSync();
        await _sendJson(request.response, 200, assets.map((asset) {
          final map = asset.toMap()..remove('id');
          return map;
        }).toList());
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/api/assets/delete') {
        final decoded = await _readJsonBody(request);
        if (decoded is! Map || decoded['uuid'] is! String) {
          await _sendJson(request.response, 400, {'error': 'Invalid asset deletion data.'});
          return;
        }
        final uuid = decoded['uuid'] as String;
        await _assetRepository.markDeletedPendingByUuid(uuid);
        await _sendJson(request.response, 200, {'status': 'ok', 'uuid': uuid});
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/api/assets') {
        final decoded = await _readJsonBody(request);
        if (decoded is! Map) {
          await _sendJson(request.response, 400, {'error': 'Invalid asset data.'});
          return;
        }
        var asset = Asset.fromMap(Map<String, Object?>.from(decoded));
        final existingAsset = await _assetRepository.getByUuid(asset.uuid);
        if (existingAsset != null) {
          // The Windows-generated asset code is canonical for this UUID.
          asset = asset.copyWith(assetCode: existingAsset.assetCode);
        } else {
          // Asset codes are local-ID-derived on each device. Allocate a
          // Windows code before inserting an offline-created Android asset.
          asset = asset.copyWith(assetCode: _nextAvailableAssetCode(await _assetRepository.getAllForSync()));
        }
        final applied = await _assetRepository.upsertFromSync(asset);
        if (!applied) {
          await _sendJson(request.response, 409, {'error': 'Asset could not be applied.', 'uuid': asset.uuid});
          return;
        }
        await _sendJson(request.response, 200, {'status': 'ok', 'uuid': asset.uuid});
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/api/customers') {
        final customers = await _customerRepository.getAll();

        await _sendJson(
          request.response,
          200,
          customers
              .map(
                (customer) => customer.toMap()
                  ..remove('id')
                  ..remove('sync_status'),
              )
              .toList(),
        );
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/api/customers') {
        final decoded = await _readJsonBody(request);
        if (decoded is! Map) {
          await _sendJson(request.response, 400, {
            'error': 'Invalid customer data.',
          });
          return;
        }

        final customer = Customer.fromMap(Map<String, Object?>.from(decoded));

        final applied = await _customerRepository.upsertFromSync(customer);

        if (!applied) {
          await _sendJson(request.response, 409, {
            'error': 'Customer could not be applied.',
            'uuid': customer.uuid,
          });
          return;
        }

        await _sendJson(request.response, 200, {
          'status': 'ok',
          'uuid': customer.uuid,
        });
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/api/invoices') {
        final invoices = await _invoiceRepository.getAll();
        final payload = <Map<String, Object?>>[];

        for (final invoice in invoices) {
          final items = await _invoiceRepository.getItems(invoice.id!);
          payload.add(SyncInvoice(invoice: invoice, items: items).toMap());
        }

        await _sendJson(request.response, 200, payload);
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/api/invoices') {
        final decoded = await _readJsonBody(request);
        if (decoded is! Map) {
          await _sendJson(request.response, 400, {
            'error': 'Invalid invoice data.',
          });
          return;
        }

        final map = Map<String, Object?>.from(decoded);
        final uuid = map['uuid'];
        final invoiceNumber = map['invoice_number'];
        final customerUuid = map['customer_uuid'];
        final orderUuid = map['order_uuid'];
        if (uuid is! String ||
            uuid.trim().isEmpty ||
            invoiceNumber is! String ||
            invoiceNumber.trim().isEmpty ||
            customerUuid is! String ||
            customerUuid.trim().isEmpty ||
            orderUuid is! String ||
            orderUuid.trim().isEmpty) {
          await _sendJson(request.response, 400, {
            'error': 'Invoice UUID, number, customer and order are required.',
          });
          return;
        }

        final syncInvoice = SyncInvoice.fromMap(
          map,
          customerId: 0,
          orderId: 0,
        );

        try {
          final canonical = await _invoiceRepository.reconcileFromSync(
            syncInvoice.invoice,
            syncInvoice.items,
          );
          final canonicalPayload = SyncInvoice(
            invoice: canonical.invoice,
            items: canonical.items,
          ).toMap();

          await _sendJson(request.response, 200, {
            'status': 'ok',
            'uuid': canonical.invoice.uuid,
            'invoice_number': canonical.invoice.invoiceNumber,
            'canonical_invoice': canonicalPayload,
          });
        } on StateError catch (error) {
          await _sendJson(request.response, 409, {
            'error': error.message,
            'uuid': syncInvoice.invoice.uuid,
          });
        }
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/api/bills') {
        final bills = await _billRepository.getAll();

        final payload = <Map<String, Object?>>[];
        for (final bill in bills) {
          final items = await _billRepository.getItems(bill.id!);
          payload.add(SyncBill(bill: bill, items: items).toMap());
        }

        await _sendJson(request.response, 200, payload);
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/api/bills') {
        final decoded = await _readJsonBody(request);
        if (decoded is! Map) {
          await _sendJson(request.response, 400, {
            'error': 'Invalid bill data.',
          });
          return;
        }

        final map = Map<String, Object?>.from(decoded);
        final uuid = map['uuid'];
        final billNumber = map['bill_number'];
        final customerUuid = map['customer_uuid'];
        final orderUuid = map['order_uuid'];
        if (uuid is! String ||
            uuid.trim().isEmpty ||
            billNumber is! String ||
            billNumber.trim().isEmpty ||
            customerUuid is! String ||
            customerUuid.trim().isEmpty ||
            (orderUuid != null &&
                (orderUuid is! String || orderUuid.trim().isEmpty))) {
          await _sendJson(request.response, 400, {
            'error': 'Bill UUID, number and customer are required.',
          });
          return;
        }

        final syncBill = SyncBill.fromMap(map);
        try {
          final canonical = await _billRepository.reconcileFromSync(
            syncBill.bill,
            syncBill.items,
          );
          final canonicalPayload = SyncBill(
            bill: canonical.bill,
            items: canonical.items,
          ).toMap();

          await _sendJson(request.response, 200, {
            'status': 'ok',
            'uuid': canonical.bill.uuid,
            'bill_number': canonical.bill.billNumber,
            'canonical_bill': canonicalPayload,
          });
        } on StateError catch (error) {
          await _sendJson(request.response, 409, {
            'error': error.message,
            'uuid': syncBill.bill.uuid,
          });
        }
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/api/orders') {
        final requestedLimit = int.tryParse(request.uri.queryParameters['limit'] ?? '');
        final orders = requestedLimit == null
            ? await _orderRepository.getAll()
            : await _orderRepository.getRecent(limit: requestedLimit);
        final payload = <Map<String, Object?>>[];

        for (final order in orders) {
          final customer = await _customerRepository.getById(order.customerId);
          if (customer == null) continue;

          final items = await _orderRepository.getItems(order.id!);
          payload.add(
            SyncOrder(
              order: order,
              items: items,
              customerUuid: customer.uuid,
            ).toMap(),
          );
        }

        await _sendJson(request.response, 200, payload);
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/api/orders') {
        final decoded = await _readJsonBody(request);
        if (decoded is! Map) {
          await _sendJson(request.response, 400, {
            'error': 'Invalid order data.',
          });
          return;
        }

        final map = Map<String, Object?>.from(decoded);
        final customerUuid = map['customer_uuid'] as String?;
        final orderUuid = map['uuid'];
        final orderNumber = map['order_number'];
        if (customerUuid == null ||
            customerUuid.trim().isEmpty ||
            orderUuid is! String ||
            orderUuid.trim().isEmpty ||
            orderNumber is! String ||
            orderNumber.trim().isEmpty) {
          await _sendJson(request.response, 400, {
            'error': 'Order UUID, number and customer are required.',
          });
          return;
        }

        final syncOrder = SyncOrder.fromMap(
          map,
          customerId: 0,
        );

        try {
          final canonical = await _orderRepository.reconcileFromSync(
            syncOrder.order,
            syncOrder.items,
            customerUuid: customerUuid,
          );
          final canonicalPayload = SyncOrder(
            order: canonical.order,
            items: canonical.items,
            customerUuid: canonical.customerUuid,
          ).toMap();

          await _sendJson(request.response, 200, {
            'status': 'ok',
            'uuid': canonical.order.uuid,
            'order_number': canonical.order.orderNumber,
            'canonical_order': canonicalPayload,
          });
        } on StateError catch (error) {
          await _sendJson(request.response, 409, {
            'error': error.message,
            'uuid': syncOrder.order.uuid,
          });
        }
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/api/expenses') {
        final expenses = await _expenseRepository.getAllForSync();

        await _sendJson(
          request.response,
          200,
          expenses
              .map((expense) {
                final map = expense.toMap()..remove('id');
                // Keep the tombstone status on the wire. A deleted expense
                // must not be interpreted by the client as a live expense.
                return map;
              })
              .toList(),
        );
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/api/expenses/delete') {
        final decoded = await _readJsonBody(request);
        if (decoded is! Map || decoded['uuid'] is! String) {
          await _sendJson(request.response, 400, {
            'error': 'Invalid expense deletion data.',
          });
          return;
        }

        final uuid = decoded['uuid'] as String;
        await _expenseRepository.markDeletedPendingByUuid(uuid);

        await _sendJson(request.response, 200, {
          'status': 'ok',
          'uuid': uuid,
        });
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/api/expenses') {
        final decoded = await _readJsonBody(request);
        if (decoded is! Map) {
          await _sendJson(request.response, 400, {
            'error': 'Invalid expense data.',
          });
          return;
        }

        final expense = Expense.fromMap(Map<String, Object?>.from(decoded));
        final applied = await _expenseRepository.upsertFromSync(expense);

        if (!applied) {
          await _sendJson(request.response, 409, {
            'error': 'Expense could not be applied.',
            'uuid': expense.uuid,
          });
          return;
        }

        await _sendJson(request.response, 200, {
          'status': 'ok',
          'uuid': expense.uuid,
        });
        return;
      }

      await _sendJson(request.response, 404, {'error': 'Not found'});
    } on FormatException {
      await _sendJson(request.response, 400, {
        'error': 'Malformed request body.',
      });
    } catch (e) {
      await _sendJson(request.response, 500, {
        'error': 'Internal server error',
      });
    }
  }

  String _nextAvailableAssetCode(List<Asset> assets) {
    var highest = 0;
    for (final asset in assets) {
      if (!asset.assetCode.startsWith('AST-')) continue;
      final number = int.tryParse(asset.assetCode.substring(4));
      if (number != null && number > highest) highest = number;
    }
    return 'AST-${(highest + 1).toString().padLeft(4, '0')}';
  }

  Future<Object?> _readJsonBody(HttpRequest request) async {
    final contentLength = request.contentLength;
    if (contentLength > _maxBodyBytes) {
      throw const FormatException('Request body too large.');
    }

    final body = await utf8.decodeStream(request);
    return jsonDecode(body);
  }

  Future<void> _sendJson(
    HttpResponse response,
    int statusCode,
    Object data,
  ) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
    await response.close();
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
