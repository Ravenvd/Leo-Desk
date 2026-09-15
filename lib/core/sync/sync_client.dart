import 'dart:convert';
import 'dart:io';

import '../../features/billing/models/bill.dart';
import '../../features/billing/models/bill_item.dart';
import '../../features/customers/models/customer.dart';
import '../../features/expenses/models/expense.dart';

/// A bill bundled with its line items, as transferred over sync.
class SyncBill {
  final Bill bill;
  final List<BillItem> items;

  const SyncBill({required this.bill, required this.items});

  Map<String, Object?> toMap() {
    final billMap = bill.toMap()
      ..remove('id')
      ..remove('customer_id')
      ..remove('sync_status');
    return {
      ...billMap,
      'items': items
          .map(
            (item) => item.toMap()
              ..remove('id')
              ..remove('bill_id'),
          )
          .toList(),
    };
  }

  factory SyncBill.fromMap(Map<String, Object?> map) {
    final rawItems = map['items'];

    final items = rawItems is List
        ? rawItems
              .map(
                (item) =>
                    BillItem.fromMap(Map<String, Object?>.from(item as Map)),
              )
              .toList()
        : <BillItem>[];

    final billMap = Map<String, Object?>.from(map)..remove('items');

    return SyncBill(bill: Bill.fromMap(billMap), items: items);
  }
}

class SyncClient {
  final String serverAddress;
  final int port;
  final String token;
  final Duration timeout;

  SyncClient({
    required this.serverAddress,
    this.port = 8080,
    this.token = 'leo-desk-sync-v1',
    this.timeout = const Duration(seconds: 5),
  });

  Uri _uri(String path) => Uri.parse('http://$serverAddress:$port$path');

  Future<HttpClientRequest> _send(
    HttpClient client,
    Future<HttpClientRequest> Function() open,
  ) async {
    final request = await open().timeout(timeout);
    request.headers.set('X-Leo-Sync-Token', token);
    return request;
  }

  Future<bool> checkConnection() async {
    final client = HttpClient()..connectionTimeout = timeout;

    try {
      final request = await _send(
        client,
        () => client.getUrl(_uri('/api/health')),
      );

      final response = await request.close().timeout(timeout);

      if (response.statusCode != HttpStatus.ok) {
        return false;
      }

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);

      final data = jsonDecode(body);

      return data['status'] == 'ok' && data['service'] == 'leo-desk-sync';
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  Future<List<Customer>> fetchCustomers() async {
    final decoded = await _getJson('/api/customers');

    if (decoded is! List) {
      throw const FormatException('Invalid customers response.');
    }

    return decoded
        .map((item) => Customer.fromMap(Map<String, Object?>.from(item as Map)))
        .toList();
  }

  Future<bool> sendCustomer(Customer customer) async {
    final map = customer.toMap()
      ..remove('id')
      ..remove('sync_status');
    return _postJson('/api/customers', map, customer.uuid);
  }

  Future<List<SyncBill>> fetchBills() async {
    final decoded = await _getJson('/api/bills');

    if (decoded is! List) {
      throw const FormatException('Invalid bills response.');
    }

    return decoded
        .map((item) => SyncBill.fromMap(Map<String, Object?>.from(item as Map)))
        .toList();
  }

  Future<bool> sendBill(SyncBill bill) async {
    return _postJson('/api/bills', bill.toMap(), bill.bill.uuid);
  }

  Future<List<Expense>> fetchExpenses() async {
    final decoded = await _getJson('/api/expenses');

    if (decoded is! List) {
      throw const FormatException('Invalid expenses response.');
    }

    return decoded
        .map((item) => Expense.fromMap(Map<String, Object?>.from(item as Map)))
        .toList();
  }

  Future<bool> sendExpense(Expense expense) async {
    final map = expense.toMap()
      ..remove('id')
      ..remove('sync_status');
    return _postJson('/api/expenses', map, expense.uuid);
  }

  Future<Object?> _getJson(String path) async {
    final client = HttpClient()..connectionTimeout = timeout;

    try {
      final request = await _send(client, () => client.getUrl(_uri(path)));

      final response = await request.close().timeout(timeout);

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'GET $path failed. Status code: ${response.statusCode}',
          uri: request.uri,
        );
      }

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);

      return jsonDecode(body);
    } finally {
      client.close();
    }
  }

  Future<bool> _postJson(
    String path,
    Map<String, Object?> payload,
    String expectedUuid,
  ) async {
    final client = HttpClient()..connectionTimeout = timeout;

    try {
      final request = await _send(client, () => client.postUrl(_uri(path)));

      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));

      final response = await request.close().timeout(timeout);

      if (response.statusCode != HttpStatus.ok) {
        return false;
      }

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);

      final data = jsonDecode(body);

      return data['status'] == 'ok' && data['uuid'] == expectedUuid;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }
}
