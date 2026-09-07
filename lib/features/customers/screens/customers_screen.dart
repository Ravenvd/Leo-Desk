import 'package:flutter/material.dart';

import '../models/customer.dart';
import '../repositories/customer_repository.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({
    super.key,
    required this.repository,
  });

  final CustomerRepository repository;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _searchController = TextEditingController();

  List<Customer> _customers = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final customers = await widget.repository.getAll();

      if (!mounted) return;

      setState(() {
        _customers = customers;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = 'Unable to load customers.';
        _isLoading = false;
      });
    }
  }

  Future<void> _searchCustomers(String query) async {
    try {
      final customers = await widget.repository.search(query);

      if (!mounted) return;

      setState(() {
        _customers = customers;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = 'Unable to search customers.';
      });
    }
  }

  Future<void> _deleteCustomer(Customer customer) async {
    if (customer.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete customer?'),
          content: Text(
            'Are you sure you want to delete ${customer.name}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await widget.repository.delete(customer.id!);
    await _loadCustomers();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 28),
            _buildSearchBar(),
            const SizedBox(height: 24),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Customers',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_customers.length} customer${_customers.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: () {
            // Add customer screen will be added next.
          },
          icon: const Icon(Icons.person_add_rounded),
          label: const Text('Add Customer'),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: TextField(
        controller: _searchController,
        onChanged: _searchCustomers,
        decoration: InputDecoration(
          hintText: 'Search by name, phone, WhatsApp or email',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    _loadCustomers();
                    setState(() {});
                  },
                  icon: const Icon(Icons.clear_rounded),
                )
              : null,
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 16),
            Text(_error!),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _loadCustomers,
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    if (_customers.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.separated(
      itemCount: _customers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final customer = _customers[index];
        return _CustomerCard(
          customer: customer,
          onDelete: () => _deleteCustomer(customer),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final hasSearch = _searchController.text.trim().isNotEmpty;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasSearch
                ? Icons.search_off_rounded
                : Icons.people_outline_rounded,
            size: 64,
          ),
          const SizedBox(height: 20),
          Text(
            hasSearch ? 'No customers found' : 'No customers yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            hasSearch
                ? 'Try a different search.'
                : 'Add your first customer to get started.',
          ),
        ],
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.customer,
    required this.onDelete,
  });

  final Customer customer;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final contact = customer.phone ??
        customer.whatsapp ??
        customer.email ??
        'No contact information';

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 10,
        ),
        leading: CircleAvatar(
          child: Text(
            customer.name.isEmpty
                ? '?'
                : customer.name.substring(0, 1).toUpperCase(),
          ),
        ),
        title: Text(
          customer.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(contact),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'delete') {
              onDelete();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'delete',
              child: Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }
}