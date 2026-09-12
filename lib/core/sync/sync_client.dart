import 'dart:convert';
import 'dart:io';

import '../../features/customers/models/customer.dart';

class SyncClient {
  final String serverAddress;
  final int port;

  SyncClient({
    required this.serverAddress,
    this.port = 8080,
  });

  Future<bool> checkConnection() async {
    final client = HttpClient();

    try {
      final request = await client.getUrl(
        Uri.parse(
          'http://$serverAddress:$port/api/health',
        ),
      );

      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        return false;
      }

      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);

      return data['status'] == 'ok' &&
          data['service'] == 'leo-desk-sync';
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }
  Future<List<Customer>> fetchCustomers() async {
  final client = HttpClient();

  try {
    final request = await client.getUrl(
      Uri.parse(
        'http://$serverAddress:$port/api/customers',
      ),
    );

    final response = await request.close();

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Failed to fetch customers. '
        'Status code: ${response.statusCode}',
        uri: request.uri,
      );
    }

    final body =
        await response.transform(utf8.decoder).join();

    final decoded = jsonDecode(body);

    if (decoded is! List) {
      throw const FormatException(
        'Invalid customers response.',
      );
    }

    return decoded
        .map(
          (item) => Customer.fromMap(
            Map<String, Object?>.from(item as Map),
          ),
        )
        .toList();
  } finally {
    client.close();
  }
}
}