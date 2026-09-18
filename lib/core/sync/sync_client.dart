import 'dart:convert';
import 'dart:io';

import '../../features/billing/models/bill.dart';
import '../../features/billing/models/bill_item.dart';
import '../../features/customers/models/customer.dart';
import '../../features/expenses/models/expense.dart';
import '../../features/orders/models/order.dart';
import '../../features/orders/models/order_item.dart';

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

class SyncOrder {
  final Order order;
  final List<OrderItem> items;
  final String customerUuid;

  const SyncOrder({
    required this.order,
    required this.items,
    required this.customerUuid,
  });

  Map<String, Object?> toMap() {
    final orderMap = order.toMap()
      ..remove('id')
      ..remove('customer_id')
      ..remove('sync_status');
    return {
      ...orderMap,
      'customer_uuid': customerUuid,
      'items': items
          .map(
            (item) => item.toMap()
              ..remove('id')
              ..remove('order_id'),
          )
          .toList(),
    };
  }

  factory SyncOrder.fromMap(
    Map<String, Object?> map, {
    required int customerId,
  }) {
    final rawItems = map['items'];
    final items = rawItems is List
        ? rawItems
              .map(
                (item) => OrderItem.fromMap(
                  Map<String, Object?>.from(item as Map)
                    ..['order_id'] = 0,
                ),
              )
              .toList()
        : <OrderItem>[];

    final orderMap = Map<String, Object?>.from(map)
      ..remove('items')
      ..remove('customer_uuid');
    orderMap['customer_id'] = customerId;

    return SyncOrder(
      order: Order.fromMap(orderMap),
      items: items,
      customerUuid: map['customer_uuid'] as String,
    );
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

  Future<List<SyncOrder>> fetchOrders({
    required Map<String, int> customerIdsByUuid,
  }) async {
    final decoded = await _getJson('/api/orders');

    if (decoded is! List) {
      throw const FormatException('Invalid orders response.');
    }

    final orders = <SyncOrder>[];
    for (final item in decoded) {
      final map = Map<String, Object?>.from(item as Map);
      final customerUuid = map['customer_uuid'] as String?;
      if (customerUuid == null) continue;

      final customerId = customerIdsByUuid[customerUuid];
      if (customerId == null) continue;

      orders.add(SyncOrder.fromMap(map, customerId: customerId));
    }
    return orders;
  }

  Future<bool> sendOrder(SyncOrder order) async {
    return _postJson('/api/orders', order.toMap(), order.order.uuid);
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
