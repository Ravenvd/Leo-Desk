import 'package:flutter/material.dart';

import '../../features/customers/repositories/customer_repository.dart';
import 'sync_client.dart';

class SyncFetchTestScreen extends StatefulWidget {
  final String serverAddress;

  const SyncFetchTestScreen({
    super.key,
    required this.serverAddress,
  });

  @override
  State<SyncFetchTestScreen> createState() =>
      _SyncFetchTestScreenState();
}

class _SyncFetchTestScreenState
    extends State<SyncFetchTestScreen> {
  String _message = 'Press the button to fetch customers.';
  bool _loading = false;

  Future<void> _fetchCustomers() async {
  setState(() {
    _loading = true;
    _message = 'Fetching customers...';
  });

  try {
    final client = SyncClient(
      serverAddress: widget.serverAddress,
    );

    final customers = await client.fetchCustomers();

    final repository = CustomerRepository();

    for (final customer in customers) {
      await repository.upsertFromSync(customer);
    }

    final localCustomers = await repository.getAll();

    if (!mounted) {
      return;
    }

    setState(() {
      _message =
          'Fetched ${customers.length} customers from Windows.\n\n'
          'Stored ${localCustomers.length} customers on tablet.\n\n'
          '${localCustomers.map((customer) => customer.name).join('\n')}';
      _loading = false;
    });
  } catch (e) {
    if (!mounted) {
      return;
    }

    setState(() {
      _message = 'Error:\n$e';
      _loading = false;
    });
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Fetch Test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _loading ? null : _fetchCustomers,
              child: Text(
                _loading
                    ? 'Fetching...'
                    : 'Fetch Customers',
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Text(_message),
              ),
            ),
          ],
        ),
      ),
    );
  }
}