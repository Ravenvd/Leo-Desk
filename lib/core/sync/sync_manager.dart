import '../../features/customers/repositories/customer_repository.dart';
import 'sync_client.dart';

class SyncManager {
  final SyncClient _client;
  final CustomerRepository _customerRepository;

  SyncManager({
    required this._client,
    CustomerRepository? customerRepository,
  }) : _customerRepository =
          customerRepository ?? CustomerRepository();

  Future<void> syncCustomers() async {
    final customers = await _client.fetchCustomers();

    for (final customer in customers) {
      await _customerRepository.upsertFromSync(customer);
    }
  }
}