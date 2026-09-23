import 'dart:convert';
import 'dart:io';

import '../../features/billing/repositories/bill_repository.dart';
import '../../features/customers/models/customer.dart';
import '../../features/customers/repositories/customer_repository.dart';
import '../../features/expenses/models/expense.dart';
import '../../features/expenses/repositories/expense_repository.dart';
import '../../features/invoices/repositories/invoice_repository.dart';
import '../../features/orders/models/order.dart';
import '../../features/orders/repositories/order_repository.dart';
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
  final String token;

  SyncServer({
    CustomerRepository? customerRepository,
    BillRepository? billRepository,
    ExpenseRepository? expenseRepository,
    InvoiceRepository? invoiceRepository,
    OrderRepository? orderRepository,
    this.token = SyncConfig.defaultToken,
  }) : _customerRepository = customerRepository ?? CustomerRepository(),
       _billRepository = billRepository ?? BillRepository(),
       _expenseRepository = expenseRepository ?? ExpenseRepository(),
       _invoiceRepository = invoiceRepository ?? InvoiceRepository(),
       _orderRepository = orderRepository ?? OrderRepository();

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

        await _sendJson(request.response, 200, {
          'status': 'ok',
          'uuid': 'ack',
        });
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

        final syncInvoice =
            SyncInvoice.fromMap(Map<String, Object?>.from(decoded),
              customerId: 0,
              orderId: 0,
            );

        final customerUuid = syncInvoice.invoice.customerUuid;
        final customer = customerUuid == null
            ? null
            : await _customerRepository.getByUuid(customerUuid);
        final order = (await _orderRepository.getAll())
            .where((candidate) => candidate.uuid == syncInvoice.invoice.orderUuid)
            .cast()
            .toList();

        if (customer == null || order.isEmpty) {
          await _sendJson(request.response, 409, {
            'error': 'Invoice customer or order does not exist.',
            'uuid': syncInvoice.invoice.uuid,
          });
          return;
        }

        final applied = await _invoiceRepository.upsertFromSync(
          syncInvoice.invoice.copyWith(
            customerId: customer.id!,
            orderId: order.first.id!,
          ),
          syncInvoice.items,
        );

        if (!applied) {
          await _sendJson(request.response, 409, {
            'error': 'Invoice could not be applied.',
            'uuid': syncInvoice.invoice.uuid,
          });
          return;
        }

        await _sendJson(request.response, 200, {
          'status': 'ok',
          'uuid': syncInvoice.invoice.uuid,
        });
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

        final syncBill = SyncBill.fromMap(Map<String, Object?>.from(decoded));

        final applied = await _billRepository.upsertFromSync(
          syncBill.bill,
          syncBill.items,
        );

        if (!applied) {
          await _sendJson(request.response, 409, {
            'error': 'Bill could not be applied.',
            'uuid': syncBill.bill.uuid,
          });
          return;
        }

        await _sendJson(request.response, 200, {
          'status': 'ok',
          'uuid': syncBill.bill.uuid,
        });
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
        if (customerUuid == null) {
          await _sendJson(request.response, 400, {
            'error': 'Order customer is required.',
          });
          return;
        }

        final customer = await _customerRepository.getByUuid(customerUuid);
        if (customer == null) {
          await _sendJson(request.response, 409, {
            'error': 'Order customer does not exist.',
            'uuid': map['uuid'],
          });
          return;
        }

        var syncOrder = SyncOrder.fromMap(
          map,
          customerId: customer.id!,
        );

        final existingOrders = await _orderRepository.getAll();
        final existingByUuid = existingOrders
            .where((candidate) => candidate.uuid == syncOrder.order.uuid)
            .firstOrNull;
        final numberOwner = existingOrders
            .where(
              (candidate) =>
                  candidate.orderNumber == syncOrder.order.orderNumber &&
                  candidate.uuid != syncOrder.order.uuid,
            )
            .firstOrNull;

        // UUID is the sync identity. If a genuinely new offline order happens
        // to have the same locally generated order number as an existing
        // Windows order, allocate the next Windows order number instead of
        // failing on SQLite's UNIQUE constraint.
        if (numberOwner != null) {
          if (existingByUuid == null) {
            final nextNumber = _nextAvailableOrderNumber(existingOrders);
            syncOrder = SyncOrder(
              order: syncOrder.order.copyWith(orderNumber: nextNumber),
              items: syncOrder.items,
              customerUuid: syncOrder.customerUuid,
            );
          } else {
            await _sendJson(request.response, 409, {
              'error':
                  'Order number conflicts with another order on Windows.',
              'uuid': syncOrder.order.uuid,
              'order_number': syncOrder.order.orderNumber,
            });
            return;
          }
        }

        final applied = await _orderRepository.upsertFromSync(
          syncOrder.order,
          syncOrder.items,
        );

        if (!applied) {
          await _sendJson(request.response, 409, {
            'error': 'Order could not be applied.',
            'uuid': syncOrder.order.uuid,
          });
          return;
        }

        await _sendJson(request.response, 200, {
          'status': 'ok',
          'uuid': syncOrder.order.uuid,
          'order_number': syncOrder.order.orderNumber,
        });
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

  String _nextAvailableOrderNumber(List<Order> orders) {
    var highest = 0;
    for (final order in orders) {
      if (!order.orderNumber.startsWith('ORD-')) continue;
      final number = int.tryParse(order.orderNumber.substring(4));
      if (number != null && number > highest) {
        highest = number;
      }
    }
    return 'ORD-${(highest + 1).toString().padLeft(6, '0')}';
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
