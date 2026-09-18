import 'package:flutter/material.dart';

import '../../customers/models/customer.dart';
import '../../customers/repositories/customer_repository.dart';
import '../models/order_item.dart';
import '../services/order_creation_service.dart';

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({
    super.key,
    this.customer,
    this.customerRepository,
    this.creationService,
  });

  final Customer? customer;
  final CustomerRepository? customerRepository;
  final OrderCreationService? creationService;

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  late final CustomerRepository _customerRepository;
  late final OrderCreationService _creationService;

  Customer? _customer;
  bool _stitchingRequired = false;
  bool _isSaving = false;

  final _notesController = TextEditingController();
  final List<_OrderItemForm> _items = [];

  @override
  void initState() {
    super.initState();
    _customerRepository = widget.customerRepository ?? CustomerRepository();
    _creationService = widget.creationService ?? OrderCreationService();
    _customer = widget.customer;
    _addItem();
  }

  @override
  void dispose() {
    _notesController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _addItem() {
    setState(() {
      _items.add(_OrderItemForm());
    });
  }

  void _removeItem(int index) {
    if (_items.length == 1) return;
    final item = _items.removeAt(index);
    item.dispose();
    setState(() {});
  }

  Future<void> _selectCustomer() async {
    final customers = await _customerRepository.getAll();
    if (!mounted) return;

    final selected = await showDialog<Customer>(
      context: context,
      builder: (_) => _CustomerPickerDialog(customers: customers),
    );

    if (selected != null && mounted) {
      setState(() {
        _customer = selected;
      });
    }
  }

  Future<void> _createOrder() async {
    if (_customer?.id == null) {
      _showError('Please select a customer.');
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
    });

    try {
      final drafts = _items
          .map(
            (item) => OrderItemDraft(
              workType: item.workType,
              garmentType: item.garmentType,
              quantity: int.parse(item.quantityController.text.trim()),
              unitPricePaise: _parseAmountToPaise(
                item.unitPriceController.text,
              ),
              notes: _nullableValue(item.notesController.text),
            ),
          )
          .toList();

      final order = await _creationService.create(
        customerId: _customer!.id!,
        stitchingRequired: _stitchingRequired,
        items: drafts,
        notes: _nullableValue(_notesController.text),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order ${order.orderNumber} created.')),
      );
      Navigator.of(context).pop(order);
    } catch (error, stackTrace) {
      debugPrint('Order creation error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });
      _showError('Unable to create order: $error');
    }
  }

  int _parseAmountToPaise(String value) {
    final amount = double.tryParse(value.trim().replaceAll(',', ''));
    if (amount == null) {
      throw ArgumentError('Invalid price.');
    }
    return (amount * 100).round();
  }

  String? _nullableValue(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _formatDeliveryEstimate() {
    final duration = _stitchingRequired ? '5 days' : '72 hours';
    return 'Expected delivery: $duration from order creation';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Order')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(32),
                children: [
                  Text(
                    'New order',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Create an order for a customer and add the work to be completed.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 28),
                  _buildCustomerSection(),
                  const SizedBox(height: 20),
                  _buildStitchingSection(),
                  const SizedBox(height: 20),
                  _buildItemsSection(),
                  const SizedBox(height: 20),
                  _buildNotesSection(),
                  const SizedBox(height: 28),
                  _buildActions(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomerSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Customer',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _isSaving ? null : _selectCustomer,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Select customer *',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  _customer?.name ?? 'Choose a customer',
                  style: _customer == null
                      ? Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          )
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStitchingSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Stitching required'),
          subtitle: Text(_formatDeliveryEstimate()),
          value: _stitchingRequired,
          onChanged: _isSaving
              ? null
              : (value) {
                  setState(() {
                    _stitchingRequired = value;
                  });
                },
        ),
      ),
    );
  }

  Widget _buildItemsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Order Items',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _addItem,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add Item'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...List.generate(
              _items.length,
              (index) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildItemCard(index),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(int index) {
    final item = _items[index];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Item ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (_items.length > 1)
                IconButton(
                  onPressed: _isSaving ? null : () => _removeItem(index),
                  tooltip: 'Remove item',
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 600;

              final fields = [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: item.workType,
                    decoration: const InputDecoration(
                      labelText: 'Work type',
                      border: OutlineInputBorder(),
                    ),
                    items: OrderItem.workTypes
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              item.workType = value;
                            });
                          },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: item.garmentType,
                    decoration: const InputDecoration(
                      labelText: 'Garment',
                      border: OutlineInputBorder(),
                    ),
                    items: OrderItem.garmentTypes
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              item.garmentType = value;
                            });
                          },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: item.quantityController,
                    enabled: !_isSaving,
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final quantity = int.tryParse(value?.trim() ?? '');
                      if (quantity == null || quantity <= 0) {
                        return 'Enter quantity';
                      }
                      return null;
                    },
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: item.unitPriceController,
                    enabled: !_isSaving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) {
                      final amount = double.tryParse(
                        value?.trim().replaceAll(',', '') ?? '',
                      );
                      if (amount == null || amount < 0) {
                        return 'Enter price';
                      }
                      return null;
                    },
                    decoration: const InputDecoration(
                      labelText: 'Rate / piece',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ];

              if (compact) {
                return Column(
                  children: fields
                      .map(
                        (field) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: field,
                        ),
                      )
                      .toList(),
                );
              }

              return Row(children: fields);
            },
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: item.notesController,
            enabled: !_isSaving,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Item notes',
              hintText: 'Optional',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: TextFormField(
          controller: _notesController,
          enabled: !_isSaving,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Order notes',
            hintText: 'Optional notes for this order',
            prefixIcon: Icon(Icons.notes_outlined),
            alignLabelWithHint: true,
          ),
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: _isSaving ? null : _createOrder,
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: Text(_isSaving ? 'Creating...' : 'Create Order'),
        ),
      ],
    );
  }
}

class _OrderItemForm {
  String workType = OrderItem.workTypes.first;
  String garmentType = OrderItem.garmentTypes.first;

  final quantityController = TextEditingController(text: '1');
  final unitPriceController = TextEditingController(text: '0.00');
  final notesController = TextEditingController();

  void dispose() {
    quantityController.dispose();
    unitPriceController.dispose();
    notesController.dispose();
  }
}

class _CustomerPickerDialog extends StatefulWidget {
  const _CustomerPickerDialog({required this.customers});

  final List<Customer> customers;

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final customers = widget.customers.where((customer) {
      return customer.name.toLowerCase().contains(query) ||
          (customer.phone?.toLowerCase().contains(query) ?? false) ||
          (customer.whatsapp?.toLowerCase().contains(query) ?? false);
    }).toList();

    return AlertDialog(
      title: const Text('Select Customer'),
      content: SizedBox(
        width: 500,
        height: 500,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search customers',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: customers.isEmpty
                  ? const Center(child: Text('No customers found.'))
                  : ListView.separated(
                      itemCount: customers.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final customer = customers[index];
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              customer.name.isEmpty
                                  ? '?'
                                  : customer.name[0].toUpperCase(),
                            ),
                          ),
                          title: Text(customer.name),
                          subtitle: Text(
                            customer.phone ??
                                customer.whatsapp ??
                                'No contact information',
                          ),
                          onTap: () => Navigator.of(context).pop(customer),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
