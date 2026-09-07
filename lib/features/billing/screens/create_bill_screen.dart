import 'package:flutter/material.dart';

import '../../customers/models/customer.dart';
import '../models/bill.dart';
import '../models/bill_item.dart';
import '../repositories/bill_repository.dart';

class CreateBillScreen extends StatefulWidget {
  const CreateBillScreen({
    super.key,
    required this.customer,
    required this.repository,
  });

  final Customer customer;
  final BillRepository repository;

  @override
  State<CreateBillScreen> createState() => _CreateBillScreenState();
}

class _CreateBillScreenState extends State<CreateBillScreen> {
  final _formKey = GlobalKey<FormState>();
  final _discountController = TextEditingController(text: '0');
  final _taxController = TextEditingController(text: '0');
  final _amountPaidController = TextEditingController(text: '0');
  final _notesController = TextEditingController();

  DateTime _billDate = DateTime.now();
  bool _isSaving = false;

  final List<_BillLineController> _items = [
    _BillLineController(),
  ];

  @override
  void initState() {
    super.initState();
    _discountController.addListener(_refresh);
    _taxController.addListener(_refresh);
    _amountPaidController.addListener(_refresh);
  }

  @override
  void dispose() {
    _discountController
      ..removeListener(_refresh)
      ..dispose();
    _taxController
      ..removeListener(_refresh)
      ..dispose();
    _amountPaidController
      ..removeListener(_refresh)
      ..dispose();
    _notesController.dispose();

    for (final item in _items) {
      item.dispose();
    }

    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  int _rupeesToPaise(String value) {
    final amount = double.tryParse(value.trim()) ?? 0;
    return (amount * 100).round();
  }

  int get _subtotalPaise {
    return _items.fold<int>(
      0,
      (sum, item) => sum + item.amountPaise,
    );
  }

  int get _discountPaise => _rupeesToPaise(_discountController.text);

  int get _taxPaise => _rupeesToPaise(_taxController.text);

  int get _totalPaise {
    return _subtotalPaise - _discountPaise + _taxPaise;
  }

  int get _amountPaidPaise => _rupeesToPaise(_amountPaidController.text);

  int get _balanceDuePaise => _totalPaise - _amountPaidPaise;

  String _formatMoney(int paise) {
    final value = paise / 100;
    return '₹${value.toStringAsFixed(2)}';
  }

  String _generateBillNumber() {
    final now = DateTime.now();
    return 'INV-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  }

  Future<void> _selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _billDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (selected == null) return;

    setState(() {
      _billDate = selected;
    });
  }

  void _addItem() {
    setState(() {
      _items.add(_BillLineController());
    });
  }

  void _removeItem(int index) {
    if (_items.length == 1) return;

    final item = _items.removeAt(index);
    item.dispose();
    setState(() {});
  }

  Future<void> _saveBill() async {
    if (!_formKey.currentState!.validate()) return;

    if (_items.any((item) => item.descriptionController.text.trim().isEmpty)) {
      return;
    }

    if (_totalPaise < 0) {
      _showError('Total cannot be negative.');
      return;
    }

    if (_amountPaidPaise > _totalPaise) {
      _showError('Amount paid cannot be greater than the total.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final now = DateTime.now();

      final bill = Bill(
        customerId: widget.customer.id!,
        billNumber: _generateBillNumber(),
        billDate: _billDate,
        subtotalPaise: _subtotalPaise,
        discountPaise: _discountPaise,
        taxPaise: _taxPaise,
        totalPaise: _totalPaise,
        amountPaidPaise: _amountPaidPaise,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        createdAt: now,
        updatedAt: now,
      );

      final items = _items.map((item) {
        return BillItem(
          billId: 0,
          description: item.descriptionController.text.trim(),
          quantity: item.quantity,
          ratePaise: _rupeesToPaise(item.rateController.text),
          amountPaise: item.amountPaise,
        );
      }).toList();

      final billId = await widget.repository.insert(
        bill: bill,
        items: items,
      );

      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      Navigator.pop(context, billId);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to save bill: $error'),
          duration: const Duration(seconds: 6),
        ),
      );

      debugPrint('Bill save error: $error');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildMoneyField(
    TextEditingController controller,
    String label,
  ) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixText: '₹ ',
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        final amount = double.tryParse(value?.trim() ?? '');
        if (amount == null || amount < 0) {
          return 'Enter a valid amount';
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Bill'),
      ),
      body: Form(
        key: _formKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCustomerCard(),
                      const SizedBox(height: 24),
                      _buildBillInformation(),
                      const SizedBox(height: 24),
                      _buildItemsSection(),
                      const SizedBox(height: 24),
                      _buildTotalsSection(),
                      const SizedBox(height: 24),
                      _buildNotesSection(),
                      const SizedBox(height: 32),
                      _buildSaveButton(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCustomerCard() {
    final contact = widget.customer.phone ??
        widget.customer.whatsapp ??
        widget.customer.email;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              child: Text(
                widget.customer.name.isEmpty
                    ? '?'
                    : widget.customer.name.substring(0, 1).toUpperCase(),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.customer.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  if (contact != null) ...[
                    const SizedBox(height: 4),
                    Text(contact),
                  ],
                ],
              ),
            ),
            const Chip(label: Text('Customer')),
          ],
        ),
      ),
    );
  }

  Widget _buildBillInformation() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 24,
          runSpacing: 16,
          children: [
            SizedBox(
              width: 260,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Bill Number',
                  border: OutlineInputBorder(),
                ),
                child: Text(_generateBillNumber()),
              ),
            ),
            SizedBox(
              width: 260,
              child: InkWell(
                onTap: _selectDate,
                borderRadius: BorderRadius.circular(4),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Bill Date',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today_rounded),
                  ),
                  child: Text(
                    '${_billDate.day.toString().padLeft(2, '0')}/'
                    '${_billDate.month.toString().padLeft(2, '0')}/'
                    '${_billDate.year}',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Items',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add Item'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...List.generate(
              _items.length,
              (index) => _buildItemRow(index),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(int index) {
    final item = _items[index];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 650;

          final description = Expanded(
            child: TextFormField(
              controller: item.descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Required';
                }
                return null;
              },
            ),
          );

          final quantity = SizedBox(
            width: compact ? double.infinity : 110,
            child: TextFormField(
              controller: item.quantityController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Qty',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              validator: (value) {
                final quantity =
                    double.tryParse(value?.trim() ?? '');
                if (quantity == null || quantity <= 0) {
                  return 'Invalid';
                }
                return null;
              },
            ),
          );

          final rate = SizedBox(
            width: compact ? double.infinity : 150,
            child: TextFormField(
              controller: item.rateController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Rate',
                prefixText: '₹ ',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              validator: (value) {
                final rate = double.tryParse(value?.trim() ?? '');
                if (rate == null || rate < 0) {
                  return 'Invalid';
                }
                return null;
              },
            ),
          );

          final amount = SizedBox(
            width: compact ? double.infinity : 150,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Amount',
                border: OutlineInputBorder(),
              ),
              child: Text(
                _formatMoney(item.amountPaise),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          );

          final removeButton = IconButton(
            tooltip: 'Remove item',
            onPressed:
                _items.length == 1 ? null : () => _removeItem(index),
            icon: const Icon(Icons.delete_outline_rounded),
          );

          if (compact) {
            return Column(
              children: [
                description,
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: quantity),
                    const SizedBox(width: 12),
                    Expanded(child: rate),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: amount),
                    removeButton,
                  ],
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              description,
              const SizedBox(width: 12),
              quantity,
              const SizedBox(width: 12),
              rate,
              const SizedBox(width: 12),
              amount,
              removeButton,
            ],
          );
        },
      ),
    );
  }

  Widget _buildTotalsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Totals',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(height: 20),
            _buildTotalRow('Subtotal', _subtotalPaise),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: Text('Discount')),
                SizedBox(
                  width: 180,
                  child: _buildMoneyField(
                    _discountController,
                    'Discount',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: Text('Tax')),
                SizedBox(
                  width: 180,
                  child: _buildMoneyField(
                    _taxController,
                    'Tax',
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            _buildTotalRow(
              'Total',
              _totalPaise,
              emphasized: true,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: Text('Amount Paid')),
                SizedBox(
                  width: 180,
                  child: _buildMoneyField(
                    _amountPaidController,
                    'Paid',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildTotalRow(
              'Balance Due',
              _balanceDuePaise,
              emphasized: true,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Chip(
                label: Text(
                  _amountPaidPaise <= 0
                      ? 'Unpaid'
                      : _amountPaidPaise >= _totalPaise
                          ? 'Paid'
                          : 'Partial',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalRow(
    String label,
    int amountPaise, {
    bool emphasized = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: emphasized
                ? const TextStyle(fontWeight: FontWeight.w700)
                : null,
          ),
        ),
        Text(
          _formatMoney(amountPaise),
          style: emphasized
              ? Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  )
              : null,
        ),
      ],
    );
  }

  Widget _buildNotesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: TextField(
          controller: _notesController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Notes',
            hintText: 'Optional notes for this bill',
            border: OutlineInputBorder(),
          ),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _isSaving ? null : _saveBill,
        icon: _isSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save_rounded),
        label: Text(_isSaving ? 'Saving...' : 'Save Bill'),
      ),
    );
  }
}

class _BillLineController {
  final descriptionController = TextEditingController();
  final quantityController = TextEditingController(text: '1');
  final rateController = TextEditingController(text: '0');

  double get quantity {
    return double.tryParse(quantityController.text.trim()) ?? 0;
  }

  int get ratePaise {
    final rate = double.tryParse(rateController.text.trim()) ?? 0;
    return (rate * 100).round();
  }

  int get amountPaise {
    return (quantity * ratePaise).round();
  }

  void dispose() {
    descriptionController.dispose();
    quantityController.dispose();
    rateController.dispose();
  }
}
