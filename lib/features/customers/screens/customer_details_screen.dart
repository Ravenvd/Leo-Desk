import 'package:flutter/material.dart';

import '../../orders/models/order.dart';
import '../../orders/repositories/order_repository.dart';
import '../../orders/screens/order_details_screen.dart';
import '../models/customer.dart';
import '../repositories/customer_repository.dart';
import 'customer_form_screen.dart';

class CustomerDetailsScreen extends StatefulWidget {
  const CustomerDetailsScreen({
    super.key,
    required this.repository,
    required this.customer,
  });

  final CustomerRepository repository;
  final Customer customer;

  @override
  State<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen> {
  late Customer _customer;
  final OrderRepository _orderRepository = OrderRepository();

  List<Order> _orders = [];
  bool _isLoadingHistory = true;
  String? _historyError;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    _loadOrderHistory();
  }

  Future<void> _loadOrderHistory() async {
    final customerId = _customer.id;

    if (customerId == null) {
      setState(() {
        _orders = [];
        _isLoadingHistory = false;
        _historyError = null;
      });
      return;
    }

    setState(() {
      _isLoadingHistory = true;
      _historyError = null;
    });

    try {
      final orders = await _orderRepository.getByCustomer(customerId);

      if (!mounted) return;

      setState(() {
        _orders = orders;
        _isLoadingHistory = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Load customer bill history error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _isLoadingHistory = false;
        _historyError = 'Unable to load order history.';
      });
    }
  }

  Future<void> _editCustomer() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(
          repository: widget.repository,
          customer: _customer,
        ),
      ),
    );

    if (!mounted || result != true || _customer.id == null) return;

    try {
      final updated = await widget.repository.getById(_customer.id!);

      if (!mounted) return;

      if (updated != null) {
        setState(() {
          _customer = updated;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Reload customer error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year}';
  }

  String _formatMoney(int paise) {
    return '₹${(paise / 100).toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Details'),
        actions: [
          IconButton(
            onPressed: _editCustomer,
            tooltip: 'Edit customer',
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ListView(
              padding: const EdgeInsets.all(32),
              children: [
                _buildProfileHeader(),
                const SizedBox(height: 24),
                _buildInformationCard(),
                const SizedBox(height: 24),
                _buildHistorySection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    final initial = _customer.name.isEmpty
        ? '?'
        : _customer.name.substring(0, 1).toUpperCase();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Row(
          children: [
            CircleAvatar(
              radius: 34,
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _customer.name,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),

                 ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInformationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Customer Information',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            _InfoRow(
              icon: Icons.phone_outlined,
              label: 'Phone',
              value: _customer.phone ?? 'Not provided',
            ),
            _InfoRow(
              icon: Icons.chat_outlined,
              label: 'WhatsApp',
              value: _customer.whatsapp ?? 'Not provided',
            ),
            _InfoRow(
              icon: Icons.email_outlined,
              label: 'Email',
              value: _customer.email ?? 'Not provided',
            ),
            _InfoRow(
              icon: Icons.location_on_outlined,
              label: 'Address',
              value: _customer.address ?? 'Not provided',
            ),
            _InfoRow(
              icon: Icons.notes_outlined,
              label: 'Notes',
              value: _customer.notes ?? 'No notes',
            ),
            const Divider(height: 28),
            _InfoRow(
              icon: Icons.calendar_today_outlined,
              label: 'Customer since',
              value: _formatDate(_customer.createdAt),
            ),
            _InfoRow(
              icon: Icons.update_outlined,
              label: 'Last updated',
              value: _formatDate(_customer.updatedAt),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shopping_bag_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Customer Orders',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${_orders.length} order${_orders.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_isLoadingHistory)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_historyError != null)
              _buildHistoryError()
            else if (_orders.isEmpty)
              _buildEmptyHistory()
            else
              _buildOrderHistory(),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryError() {
    return Column(
      children: [
        const Icon(Icons.error_outline_rounded, size: 44),
        const SizedBox(height: 12),
        Text(_historyError!),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _loadOrderHistory,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try Again'),
        ),
      ],
    );
  }

  Widget _buildEmptyHistory() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            Icons.shopping_bag_outlined,
            size: 44,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text('No orders yet', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text(
            'Orders placed by this customer will appear here.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildOrderHistory() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Order')),
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Total')),
        ],
        rows: _orders.map((order) {
          return DataRow(
            cells: [
              DataCell(
                Text(order.orderNumber, style: const TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => _viewOrder(order),
              ),
              DataCell(Text(_formatDate(order.orderDate))),
              DataCell(Chip(label: Text(order.status), visualDensity: VisualDensity.compact)),
              DataCell(FutureBuilder<int>(
                future: _orderTotal(order),
                builder: (context, snapshot) => Text(
                  snapshot.hasData ? _formatMoney(snapshot.data!) : '—',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              )),
            ],
          );
        }).toList(),
      ),
    );
  }

  Future<int> _orderTotal(Order order) async {
    if (order.id == null) return order.stitchingPricePaise;
    final items = await _orderRepository.getItems(order.id!);
    return items.fold<int>(
      order.stitchingPricePaise,
      (total, item) => total + item.quantity * item.unitPricePaise,
    );
  }

  Future<void> _viewOrder(Order order) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OrderDetailsScreen(order: order)),
    );
    if (mounted) await _loadOrderHistory();
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 32, child: Icon(icon, size: 20)),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
