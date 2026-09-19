import 'package:flutter/material.dart';

import '../../billing/services/bill_creation_service.dart';

import '../../customers/models/customer.dart';
import '../../customers/repositories/customer_repository.dart';
import '../models/order.dart';
import '../models/order_item.dart';
import '../repositories/order_item_repository.dart';
import '../repositories/order_repository.dart';
import '../../invoices/services/invoice_creation_service.dart';
import 'create_order_screen.dart';

class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({
    super.key,
    required this.order,
    this.orderRepository,
    this.orderItemRepository,
    this.customerRepository,
  });

  final Order order;
  final OrderRepository? orderRepository;
  final OrderItemRepository? orderItemRepository;
  final CustomerRepository? customerRepository;

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  late Order _order;
  late final OrderRepository _orderRepository;
  late final OrderItemRepository _itemRepository;
  late final CustomerRepository _customerRepository;
  late final InvoiceCreationService _invoiceCreationService;
  late final BillCreationService _billCreationService;

  Customer? _customer;
  List<OrderItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _orderRepository = widget.orderRepository ?? OrderRepository();
    _itemRepository = widget.orderItemRepository ?? OrderItemRepository();
    _customerRepository = widget.customerRepository ?? CustomerRepository();
    _invoiceCreationService = InvoiceCreationService(
      orderRepository: _orderRepository,
      customerRepository: _customerRepository,
    );
    _billCreationService = BillCreationService(
      customerRepository: _customerRepository,
    );
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    if (_order.id == null) {
      setState(() {
        _loading = false;
        _error = 'This order does not have a local ID.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final customer = await _customerRepository.getById(_order.customerId);
      final items = await _itemRepository.getByOrder(_order.id!);

      if (!mounted) return;

      setState(() {
        _customer = customer;
        _items = items;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Load order details error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Unable to load order details.';
      });
    }
  }

  bool get _isFrozen {
    return _order.status != 'New';
  }

  bool get _isTerminal =>
      _order.status == 'Completed' || _order.status == 'Cancelled';

  int get _itemsTotalPaise => _items.fold(
        0,
        (total, item) => total + item.quantity * item.unitPricePaise,
      );

  int get _orderTotalPaise => _itemsTotalPaise + _order.stitchingPricePaise;

  String _money(int paise) => '₹${(paise / 100).toStringAsFixed(2)}';

  String _date(DateTime value) {
    final d = value.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _dateTime(DateTime value) {
    final d = value.toLocal();
    return '${_date(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _editingWindow() {
    return 'Order can be edited until it is moved to In Progress.';
  }

  Future<void> _changeStatus(String status) async {
    if (_isTerminal || _order.id == null || !_isStatusSelectable(status)) {
      return;
    }

    try {
      final updated = _order.copyWith(
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
        await _orderRepository.update(_order);
        rethrow;
      }

      if (!mounted) return;
      setState(() => _order = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'In Progress'
                ? 'Status changed to In Progress. Invoice generated.'
                : status == 'Completed'
                    ? 'Status changed to Completed. Bill generated.'
                    : 'Status changed to $status.',
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

  bool _isStatusSelectable(String status) {
    if (status == 'Cancelled') return false;
    if (status == 'Sent for Stitching' && !_order.stitchingRequired) {
      return false;
    }

    final currentIndex = Order.statuses.indexOf(_order.status);
    final targetIndex = Order.statuses.indexOf(status);
    if (currentIndex < 0 || targetIndex < 0) return false;

    return targetIndex >= currentIndex;
  }

  Future<void> _cancelOrder() async {
    if (_isTerminal) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel order?'),
        content: Text(
          'This will lock ${_order.orderNumber} and mark it as cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Order'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Order'),
          ),
        ],
      ),
    );

    if (confirmed != true || _order.id == null) return;

    try {
      final updated = _order.copyWith(
        status: 'Cancelled',
        updatedAt: DateTime.now(),
      );
      await _orderRepository.update(updated);

      if (!mounted) return;
      setState(() => _order = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order cancelled.')),
      );
    } catch (error, stackTrace) {
      debugPrint('Cancel order error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to cancel order.')),
      );
    }
  }

  Future<void> _editRate(OrderItem item) async {
    if (_isFrozen || item.id == null) return;

    final controller = TextEditingController(
      text: (item.unitPricePaise / 100).toStringAsFixed(2),
    );

    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit rate per piece'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Rate per piece',
            prefixText: '₹ ',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final amount = double.tryParse(
                controller.text.trim().replaceAll(',', ''),
              );
              if (amount != null && amount >= 0) {
                Navigator.pop(context, amount);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (value == null) return;

    try {
      await _itemRepository.update(
        item.copyWith(
          unitPricePaise: (value * 100).round(),
          updatedAt: DateTime.now(),
        ),
      );
      await _loadDetails();
    } catch (error, stackTrace) {
      debugPrint('Update order item rate error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to update the rate.')),
      );
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_order.orderNumber),
        actions: [
          if (!_isTerminal && !_isFrozen)
            IconButton(
              onPressed: () async {
                final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => CreateOrderScreen(order: _order),
                  ),
                );
                if (changed == true && mounted) {
                  await _loadDetails();
                }
              },
              tooltip: 'Edit order',
              icon: const Icon(Icons.edit_outlined),
            ),
          if (!_isTerminal)
            IconButton(
              onPressed: _cancelOrder,
              tooltip: 'Cancel order',
              icon: const Icon(Icons.cancel_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildError()
                : RefreshIndicator(
                    onRefresh: _loadDetails,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1000),
                        child: ListView(
                          padding: const EdgeInsets.all(32),
                          children: [
                            _buildHeader(),
                            const SizedBox(height: 24),
                            _buildInformation(),
                            const SizedBox(height: 24),
                            _buildItems(),
                            if (_order.notes != null &&
                                _order.notes!.trim().isNotEmpty) ...[
                              const SizedBox(height: 24),
                              _buildNotes(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 48),
          const SizedBox(height: 16),
          Text(_error!),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _loadDetails,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _order.orderNumber,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Chip(
                  avatar: Icon(
                    Icons.circle,
                    size: 12,
                    color: _statusColor(_order.status),
                  ),
                  label: Text(_order.status),
                ),
              ],
            ),
            if (_customer != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.person_outline_rounded),
                  const SizedBox(width: 12),
                  Text(
                    _customer!.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    _isFrozen
                        ? Icons.lock_outline_rounded
                        : Icons.lock_open_rounded,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isTerminal
                          ? 'This order is locked.'
                          : _isFrozen
                              ? 'Order is frozen. Details can no longer be edited.'
                              : _editingWindow(),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            if (!_isTerminal) ...[
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: _order.status,
                decoration: const InputDecoration(
                  labelText: 'Order status',
                  border: OutlineInputBorder(),
                ),
                items: Order.statuses
                    .where((status) => status != 'Cancelled')
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        enabled: _isStatusSelectable(status),
                        child: Text(status),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) _changeStatus(value);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInformation() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order Information',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 16),
            _InfoRow(
              icon: Icons.calendar_today_outlined,
              label: 'Order date',
              value: _dateTime(_order.orderDate),
            ),
            _InfoRow(
              icon: Icons.event_available_outlined,
              label: 'Expected delivery',
              value: _dateTime(_order.expectedDeliveryDate),
            ),
            _InfoRow(
              icon: Icons.content_cut_outlined,
              label: 'Stitching',
              value: _order.stitchingRequired ? 'Required' : 'Not required',
            ),
            if (_order.stitchingRequired)
              _InfoRow(
                icon: Icons.payments_outlined,
                label: 'Stitching charge',
                value: _money(_order.stitchingPricePaise),
              ),
            _InfoRow(
              icon: Icons.update_outlined,
              label: 'Last updated',
              value: _dateTime(_order.updatedAt),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItems() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order Items',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 16),
            if (_items.isEmpty)
              const Text('No items found for this order.')
            else
              ..._items.map(_buildItem),
            const Divider(height: 32),
            _TotalRow(
              label: 'Items total',
              amount: _money(_itemsTotalPaise),
            ),
            if (_order.stitchingRequired)
              _TotalRow(
                label: 'Stitching',
                amount: _money(_order.stitchingPricePaise),
              ),
            const SizedBox(height: 8),
            _TotalRow(
              label: 'Order total',
              amount: _money(_orderTotalPaise),
              emphasized: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(OrderItem item) {
    final amount = item.quantity * item.unitPricePaise;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${item.workType} · ${item.garmentType}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  _money(amount),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${item.quantity} × ${_money(item.unitPricePaise)}',
                  ),
                ),
                if (!_isFrozen)
                  IconButton(
                    onPressed: () => _editRate(item),
                    tooltip: 'Edit rate',
                    icon: const Icon(Icons.edit_outlined),
                  ),
              ],
            ),
            if (item.notes != null && item.notes!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(item.notes!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNotes() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order Notes',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            Text(_order.notes!),
          ],
        ),
      ),
    );
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
            width: 150,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.amount,
    this.emphasized = false,
  });

  final String label;
  final String amount;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            )
        : Theme.of(context).textTheme.bodyLarge;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(amount, style: style),
        ],
      ),
    );
  }
}
