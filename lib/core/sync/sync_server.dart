import 'dart:convert';
import 'dart:io';

import '../../features/billing/repositories/bill_repository.dart';
import '../../features/customers/models/customer.dart';
import '../../features/customers/repositories/customer_repository.dart';
import 'sync_client.dart';
import 'sync_config.dart';

class SyncServer {
  static const int _maxBodyBytes = 5 * 1024 * 1024;

  HttpServer? _server;

  final CustomerRepository _customerRepository;
  final BillRepository _billRepository;
  final String token;

  SyncServer({
    CustomerRepository? customerRepository,
    BillRepository? billRepository,
    this.token = SyncConfig.defaultToken,
  }) : _customerRepository = customerRepository ?? CustomerRepository(),
       _billRepository = billRepository ?? BillRepository();

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
