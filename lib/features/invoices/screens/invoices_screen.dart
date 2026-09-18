import 'package:flutter/material.dart';

import '../../customers/models/customer.dart';
import '../../customers/repositories/customer_repository.dart';
import '../../orders/models/order.dart';
import '../../orders/repositories/order_repository.dart';
import 'invoice_preview_screen.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key, this.orderRepository, this.customerRepository});

  final OrderRepository? orderRepository;
  final CustomerRepository? customerRepository;

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  late final OrderRepository _orderRepository;
  late final CustomerRepository _customerRepository;
  List<Order> _orders = [];
  Map<int, Customer> _customers = {};
  Map<int, int> _totals = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _orderRepository = widget.orderRepository ?? OrderRepository();
    _customerRepository = widget.customerRepository ?? CustomerRepository();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() { _loading = true; _error = null; });
    try {
      final orders = await _orderRepository.getAll();
      final customers = <int, Customer>{};
      final totals = <int, int>{};
      for (final order in orders) {
        final customer = await _customerRepository.getById(order.customerId);
        if (customer != null) customers[order.customerId] = customer;
        if (order.id != null) {
          final items = await _orderRepository.getItems(order.id!);
          totals[order.id!] = items.fold(
            order.stitchingPricePaise,
            (total, item) => total + item.quantity * item.unitPricePaise,
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _customers = customers;
        _totals = totals;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Load invoice orders error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Unable to load orders for invoicing.'; });
    }
  }

  Future<void> _openInvoice(Order order) async {
    if (order.id == null) return;
    try {
      final customer = _customers[order.customerId] ??
          await _customerRepository.getById(order.customerId);
      if (customer == null) {
        _message('Customer could not be found.');
        return;
      }
      final items = await _orderRepository.getItems(order.id!);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InvoicePreviewScreen(
            order: order,
            items: items,
            customer: customer,
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Open invoice error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) _message('Unable to prepare the invoice.');
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _money(int paise) => 'Rs. ' + (paise / 100).toStringAsFixed(2);

  String _date(DateTime value) {
    final d = value.toLocal();
    return d.day.toString().padLeft(2, '0') + '/' +
        d.month.toString().padLeft(2, '0') + '/' + d.year.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invoices')),
      body: SafeArea(
        child: RefreshIndicator(onRefresh: _loadOrders, child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 16),
            Text(_error!),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loadOrders,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ],
        ),
      );
    }
    if (_orders.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Text(
            'No orders available for invoicing. Orders will appear here automatically as soon as they are created.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: _orders.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, index) => _buildOrderCard(_orders[index]),
        ),
      ),
    );
  }

  Widget _buildOrderCard(Order order) {
    final customer = _customers[order.customerId];
    final total = order.id == null ? 0 : _totals[order.id!] ?? 0;
    return Card(
      child: InkWell(
        onTap: () => _openInvoice(order),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const Icon(Icons.receipt_long_outlined, size: 36),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.orderNumber, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(customer?.name ?? 'Customer unavailable'),
                    const SizedBox(height: 4),
                    Text('Order date: ' + _date(order.orderDate),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Text(_money(total), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
