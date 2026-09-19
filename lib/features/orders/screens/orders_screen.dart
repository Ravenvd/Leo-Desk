import 'package:flutter/material.dart';

import '../../customers/models/customer.dart';
import '../../customers/repositories/customer_repository.dart';
import '../models/order.dart';
import '../repositories/order_repository.dart';
import '../../billing/services/bill_creation_service.dart';
import '../../invoices/services/invoice_creation_service.dart';
import 'create_order_screen.dart';
import 'order_details_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({
    super.key,
    this.orderRepository,
    this.customerRepository,
  });

  final OrderRepository? orderRepository;
  final CustomerRepository? customerRepository;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late final OrderRepository _orderRepository;
  late final CustomerRepository _customerRepository;
  late final InvoiceCreationService _invoiceCreationService;
  late final BillCreationService _billCreationService;

  List<Order> _orders = [];
  Map<int, Customer> _customers = {};
  bool _loading = true;
  String? _error;
  String _filter = 'New';

  @override
  void initState() {
    super.initState();
    _orderRepository = widget.orderRepository ?? OrderRepository();
    _customerRepository =
        widget.customerRepository ?? CustomerRepository();
    _invoiceCreationService = InvoiceCreationService(
      orderRepository: _orderRepository,
      customerRepository: _customerRepository,
    );
    _billCreationService = BillCreationService(
      customerRepository: _customerRepository,
    );
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final orders = await _orderRepository.getAll();
      final customerIds = orders.map((order) => order.customerId).toSet();
      final customers = <int, Customer>{};

      for (final id in customerIds) {
        final customer = await _customerRepository.getById(id);
        if (customer != null) {
          customers[id] = customer;
        }
      }

      if (!mounted) return;

      setState(() {
        _orders = orders;
        _customers = customers;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Load orders error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Unable to load orders.';
      });
    }
  }

  List<Order> get _filteredOrders =>
      _orders.where((order) => order.status == _filter).toList();

  String? _nextStatus(Order order) {
    if (order.status == 'Completed' || order.status == 'Cancelled') return null;
    final currentIndex = Order.statuses.indexOf(order.status);
    if (currentIndex < 0) return null;
    for (var index = currentIndex + 1; index < Order.statuses.length; index++) {
      final status = Order.statuses[index];
      if (status == 'Cancelled') continue;
      if (status == 'Sent for Stitching' && !order.stitchingRequired) continue;
      return status;
    }
    return null;
  }

  Future<void> _goToNextProcess(Order order) async {
    final nextStatus = _nextStatus(order);
    if (nextStatus != null) await _changeStatus(order, nextStatus);
  }

  Future<void> _cancelOrder(Order order) async {
    if (order.status == 'Completed' || order.status == 'Cancelled') return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel order?'),
        content: Text('This will lock ${order.orderNumber} and mark it as cancelled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep Order')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel Order')),
        ],
      ),
    );
    if (confirmed == true) await _changeStatus(order, 'Cancelled');
  }

  Future<void> _createOrder() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CreateOrderScreen(),
      ),
    );
    if (mounted) {
      await _loadOrders();
    }
  }

  Future<void> _openOrder(Order order) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderDetailsScreen(order: order),
      ),
    );
    if (mounted) {
      await _loadOrders();
    }
  }

  bool _isStatusSelectable(Order order, String status) {
    if (status == 'Cancelled') return false;
    if (status == 'Sent for Stitching' && !order.stitchingRequired) {
      return false;
    }

    final currentIndex = Order.statuses.indexOf(order.status);
    final targetIndex = Order.statuses.indexOf(status);
    if (currentIndex < 0 || targetIndex < 0) return false;

    return targetIndex >= currentIndex;
  }

  Future<void> _changeStatus(Order order, String status) async {
    if (order.status == 'Completed' ||
        order.status == 'Cancelled' ||
        !_isStatusSelectable(order, status)) {
      return;
    }

    try {
      final updated = order.copyWith(
        status: status,
        updatedAt: DateTime.now(),
      );
      await _orderRepository.update(updated);

      try {
        if (status == 'In Progress') {
          await _invoiceCreationService.createForOrder(updated);
        } else if (status == 'Completed') {
          await _billCreationService.createForOrder(updated);
        }
      } catch (error) {
        await _orderRepository.update(
          order.copyWith(updatedAt: DateTime.now()),
        );
        rethrow;
      }

      if (!mounted) return;

      setState(() {
        final index = _orders.indexWhere((item) => item.id == order.id);
        if (index >= 0) {
          _orders[index] = updated;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'In Progress'
                ? '${order.orderNumber} → In Progress · Invoice generated'
                : status == 'Completed'
                    ? '${order.orderNumber} → Completed · Bill generated'
                    : '${order.orderNumber} → $status',
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Update order status error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to update order status.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createOrder,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Order'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadOrders,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
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
            OutlinedButton.icon(
              onPressed: _loadOrders,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            _buildFilters(),
            const SizedBox(height: 16),
            if (_filteredOrders.isEmpty)
              _buildEmptyState()
            else
              ..._filteredOrders.map(_buildOrderCard),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Order List',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        Text(
          '${_filteredOrders.length} order${_filteredOrders.length == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<String>(
        segments: [
          ...Order.statuses.map(
            (status) => ButtonSegment(
              value: status,
              label: Text(status),
            ),
          ),
        ],
        selected: {_filter},
        onSelectionChanged: (selection) {
          setState(() => _filter = selection.first);
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            const Icon(Icons.shopping_bag_outlined, size: 52),
            const SizedBox(height: 16),
            Text(
              _orders.isEmpty ? 'No orders yet' : 'No matching orders',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _orders.isEmpty
                  ? 'Create your first order using the button below.'
                  : 'Try a different status filter.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(Order order) {
    final customer = _customers[order.customerId];
    final completed = order.status == 'Completed';
    final cancelled = order.status == 'Cancelled';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: completed ? 0.55 : 1,
        child: Card(
          child: InkWell(
            onTap: () => _openOrder(order),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      cancelled
                          ? Icons.cancel_outlined
                          : Icons.shopping_bag_outlined,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.orderNumber,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(customer?.name ?? 'Customer unavailable'),
                        const SizedBox(height: 4),
                        Text(
                          'Delivery: ${_date(order.expectedDeliveryDate)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildProcessActions(order),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProcessActions(Order order) {
    final terminal = order.status == 'Completed' || order.status == 'Cancelled';
    final nextStatus = _nextStatus(order);
    if (terminal) {
      return Chip(
        avatar: Icon(order.status == 'Cancelled' ? Icons.cancel_outlined : Icons.check_circle_outline_rounded, size: 16, color: _statusColor(order.status)),
        label: Text(order.status),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          onPressed: nextStatus == null ? null : () => _goToNextProcess(order),
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          label: Text(nextStatus == 'Completed' ? 'Complete' : 'Next: $nextStatus'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => _cancelOrder(order),
          icon: const Icon(Icons.cancel_outlined, size: 18),
          label: const Text('Cancel'),
        ),
      ],
    );
  }

  Color _statusColor(String status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case 'Completed':
        return scheme.onSurfaceVariant;
      case 'Cancelled':
        return scheme.error;
      case 'Ready':
        return scheme.primary;
      case 'Sent for Stitching':
        return scheme.tertiary;
      default:
        return scheme.secondary;
    }
  }

  String _date(DateTime value) {
    final date = value.toLocal();
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
