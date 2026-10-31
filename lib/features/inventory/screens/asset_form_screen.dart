import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../repositories/asset_repository.dart';

class AssetFormScreen extends StatefulWidget {
  const AssetFormScreen({super.key, required this.repository, this.asset});

  final AssetRepository repository;
  final Asset? asset;

  bool get isEditing => asset != null;

  @override
  State<AssetFormScreen> createState() => _AssetFormScreenState();
}

class _AssetFormScreenState extends State<AssetFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _cost = TextEditingController();
  final _manufacturer = TextEditingController();
  final _serial = TextEditingController();
  final _warranty = TextEditingController();
  final _notes = TextEditingController();

  DateTime? _purchaseDate;
  String _status = Asset.statusActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = widget.asset;
    if (a != null) {
      _name.text = a.name;
      if (a.purchaseCostPaise != null) {
        _cost.text = (a.purchaseCostPaise! / 100).toStringAsFixed(2);
      }
      _manufacturer.text = a.manufacturerModel ?? '';
      _serial.text = a.serialNumber ?? '';
      _warranty.text = a.warrantyInformation ?? '';
      _notes.text = a.notes ?? '';
      _purchaseDate = a.purchaseDate;
      _status = a.status;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _cost.dispose();
    _manufacturer.dispose();
    _serial.dispose();
    _warranty.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate ?? now,
      firstDate: DateTime(1980),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null && mounted) setState(() => _purchaseDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final now = DateTime.now();
    final text = _cost.text.trim().replaceAll(',', '');
    final amount = double.tryParse(text);
    final existing = widget.asset;

    final asset = Asset(
      id: existing?.id,
      uuid: existing?.uuid,
      syncStatus: existing?.syncStatus ?? Asset.syncStatusPending,
      assetCode: existing?.assetCode,
      name: _name.text.trim(),
      purchaseDate: _purchaseDate,
      purchaseCostPaise: amount == null ? null : (amount * 100).round(),
      manufacturerModel: _optional(_manufacturer.text),
      serialNumber: _optional(_serial.text),
      warrantyInformation: _optional(_warranty.text),
      status: _status,
      notes: _optional(_notes.text),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    setState(() => _saving = true);
    try {
      if (existing == null) {
        await widget.repository.insert(asset);
      } else {
        await widget.repository.update(asset);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      debugPrint('Save asset error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save asset.')),
      );
    }
  }

  String? _optional(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _validateCost(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final amount = double.tryParse(text.replaceAll(',', ''));
    return amount == null || amount < 0 ? 'Enter a valid amount' : null;
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Asset' : 'Add Asset'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.isEditing ? 'Update asset information' : 'Add a new asset',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Record the equipment and its ownership details.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 28),
                  _section(
                    'Asset information',
                    [
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Asset name *',
                          hintText: 'e.g. Embroidery machine',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value == null || value.trim().isEmpty
                            ? 'Asset name is required'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      _readOnlyField(
                        'Asset code',
                        widget.asset?.assetCode ?? 'Generated on save',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _cost,
                        decoration: const InputDecoration(
                          labelText: 'Purchase cost',
                          prefixText: '₹ ',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: _validateCost,
                      ),
                      const SizedBox(height: 16),
                      _dateField(),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _manufacturer,
                        decoration: const InputDecoration(
                          labelText: 'Manufacturer / Model',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _serial,
                        decoration: const InputDecoration(
                          labelText: 'Serial number',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _section(
                    'Warranty & status',
                    [
                      TextFormField(
                        controller: _warranty,
                        decoration: const InputDecoration(
                          labelText: 'Warranty information',
                          hintText: 'e.g. 2 years / until 12/07/2028',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(),
                        ),
                        items: Asset.statuses
                            .map((status) => DropdownMenuItem(
                                  value: status,
                                  child: Text(status),
                                ))
                            .toList(),
                        onChanged: _saving
                            ? null
                            : (value) {
                                if (value != null) setState(() => _status = value);
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _section(
                    'Notes',
                    [
                      TextFormField(
                        controller: _notes,
                        decoration: const InputDecoration(
                          hintText: 'Additional information',
                          border: OutlineInputBorder(),
                        ),
                        minLines: 4,
                        maxLines: 6,
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(_saving
                          ? 'Saving...'
                          : widget.isEditing
                              ? 'Save changes'
                              : 'Save asset'),
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

  Widget _dateField() {
    return InkWell(
      onTap: _saving ? null : _pickDate,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Purchase date',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.calendar_today_rounded),
        ),
        child: Text(
          _purchaseDate == null ? 'Select date' : _formatDate(_purchaseDate!),
          style: _purchaseDate == null
              ? TextStyle(color: Theme.of(context).hintColor)
              : null,
        ),
      ),
    );
  }

  Widget _readOnlyField(String label, String value) {
    return InputDecorator(
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        filled: true,
      ).copyWith(labelText: label),
      child: Text(value),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}
