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
  final List<_BillLineController> _items = [_BillLineController()];

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

  int _paise(String value) {
    return ((double.tryParse(value.trim()) ?? 0) * 100).round();
  }

  int get _subtotal =>
      _items.fold(0, (sum, item) => sum + item.amountPaise);

  int get _discount => _paise(_discountController.text);
  int get _tax => _paise(_taxController.text);
  int get _total => _subtotal - _discount + _tax;
  int get _received => _paise(_amountPaidController.text);

  String _money(int paise) => 'Rs. ${(paise / 100).toStringAsFixed(2)}';

  String _billNumber() {
    final now = DateTime.now();
    return 'BILL-${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
  }

  Future<void> _saveBill() async {
    if (!_formKey.currentState!.validate()) return;

    if (_total < 0) {
      _error('Total cannot be negative.');
      return;
    }

    if (_received != _total) {
      _error('The full amount must be received before a bill can be created.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final now = DateTime.now();
      final bill = Bill(
        customerId: widget.customer.id!,
        billNumber: _billNumber(),
        billDate: _billDate,
        subtotalPaise: _subtotal,
        discountPaise: _discount,
        taxPaise: _tax,
        totalPaise: _total,
        amountPaidPaise: _received,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        createdAt: now,
        updatedAt: now,
      );

      final items = _items
          .map(
            (item) => BillItem(
              billId: 0,
              description: item.descriptionController.text.trim(),
              quantity: item.quantity,
              ratePaise: item.ratePaise,
              amountPaise: item.amountPaise,
            ),
          )
          .toList();

      final id = await widget.repository.insert(
        bill: bill,
        items: items,
      );

      if (!mounted) return;
      setState(() => _isSaving = false);
      Navigator.pop(context, id);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _error('Unable to save bill: $error');
      debugPrint('Bill save error: $error');
    }
  }

  void _error(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _billDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (date != null) {
      setState(() => _billDate = date);
    }
  }

  void _addItem() {
    setState(() => _items.add(_BillLineController()));
  }

  void _removeItem(int index) {
    if (_items.length == 1) return;
    _items.removeAt(index).dispose();
    setState(() {});
  }

  Widget _moneyField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixText: 'Rs. ',
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

  Widget _summaryRow(String label, int value, {bool bold = false}) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.w700) : null;
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(_money(value), style: style),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Bill')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _customerCard(),
                  const SizedBox(height: 20),
                  _billInfoCard(),
                  const SizedBox(height: 20),
                  _itemsCard(),
                  const SizedBox(height: 20),
                  _totalsCard(),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed:
                          _isSaving || _received != _total ? null : _saveBill,
                      icon: const Icon(Icons.receipt_long_rounded),
                      label: Text(_isSaving ? 'Saving...' : 'Save Bill'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _customerCard() {
    final initial = widget.customer.name.isEmpty
        ? '?'
        : widget.customer.name.substring(0, 1).toUpperCase();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(child: Text(initial)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                widget.customer.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
            ),
            const Chip(label: Text('Customer')),
          ],
        ),
      ),
    );
  }

  Widget _billInfoCard() {
    final formattedDate = '${_billDate.day.toString().padLeft(2, '0')}/'
        '${_billDate.month.toString().padLeft(2, '0')}/'
        '${_billDate.year}';

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
                child: Text(_billNumber()),
              ),
            ),
            SizedBox(
              width: 260,
              child: InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Bill Date',
                    border: OutlineInputBorder(),
                  ),
                  child: Text(formattedDate),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Items',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Item'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...List.generate(_items.length, _itemRow),
          ],
        ),
      ),
    );
  }

  Widget _itemRow(int index) {
    final item = _items[index];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final description = TextFormField(
            controller: item.descriptionController,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
            ),
            validator: (value) =>
                value == null || value.trim().isEmpty ? 'Required' : null,
          );

          final quantity = TextFormField(
            controller: item.quantityController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Qty',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            validator: (value) {
              final quantity = double.tryParse(value?.trim() ?? '');
              return quantity == null || quantity <= 0 ? 'Invalid' : null;
            },
          );

          final rate = TextFormField(
            controller: item.rateController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Rate',
              prefixText: 'Rs. ',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            validator: (value) {
              final rate = double.tryParse(value?.trim() ?? '');
              return rate == null || rate < 0 ? 'Invalid' : null;
            },
          );

          final amount = InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Amount',
              border: OutlineInputBorder(),
            ),
            child: Text(_money(item.amountPaise)),
          );

          final deleteButton = IconButton(
            onPressed: _items.length == 1 ? null : () => _removeItem(index),
            icon: const Icon(Icons.delete_outline),
          );

          if (constraints.maxWidth < 650) {
            return Column(
              children: [
                description,
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: quantity),
                    const SizedBox(width: 10),
                    Expanded(child: rate),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: amount),
                    deleteButton,
                  ],
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: description),
              const SizedBox(width: 10),
              SizedBox(width: 100, child: quantity),
              const SizedBox(width: 10),
              SizedBox(width: 140, child: rate),
              const SizedBox(width: 10),
              SizedBox(width: 140, child: amount),
              deleteButton,
            ],
          );
        },
      ),
    );
  }

  Widget _totalsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _summaryRow('Subtotal', _subtotal),
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(child: Text('Discount')),
                SizedBox(
                  width: 180,
                  child: _moneyField(_discountController, 'Discount'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(child: Text('Tax')),
                SizedBox(
                  width: 180,
                  child: _moneyField(_taxController, 'Tax'),
                ),
              ],
            ),
            const Divider(height: 28),
            _summaryRow('Total', _total, bold: true),
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(child: Text('Amount Received')),
                SizedBox(
                  width: 180,
                  child: _moneyField(_amountPaidController, 'Received'),
                ),
              ],
            ),
            if (_received != _total)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Full payment is required before the bill can be saved.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BillLineController {
  final descriptionController = TextEditingController();
  final quantityController = TextEditingController(text: '1');
  final rateController = TextEditingController(text: '0');

  double get quantity =>
      double.tryParse(quantityController.text.trim()) ?? 0;

  int get ratePaise =>
      ((double.tryParse(rateController.text.trim()) ?? 0) * 100).round();

  int get amountPaise => (quantity * ratePaise).round();

  void dispose() {
    descriptionController.dispose();
    quantityController.dispose();
    rateController.dispose();
  }
}
