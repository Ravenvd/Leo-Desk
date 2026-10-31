import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../models/maintenance_record.dart';
import '../repositories/maintenance_repository.dart';

class MaintenanceFormScreen extends StatefulWidget {
  const MaintenanceFormScreen({
    super.key,
    required this.repository,
    required this.asset,
    this.record,
  });

  final MaintenanceRepository repository;
  final Asset asset;
  final MaintenanceRecord? record;

  @override
  State<MaintenanceFormScreen> createState() => _MaintenanceFormScreenState();
}

class _MaintenanceFormScreenState extends State<MaintenanceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _cost = TextEditingController();
  final _notes = TextEditingController();

  late DateTime _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _date = record?.maintenanceDate ?? DateTime.now();
    _description.text = record?.description ?? '';
    if (record != null) {
      _cost.text = (record.costPaise / 100).toStringAsFixed(2);
      _notes.text = record.notes ?? '';
    }
  }

  @override
  void dispose() {
    _description.dispose();
    _cost.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1980),
      lastDate: DateTime(DateTime.now().year + 10),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_cost.text.trim().replaceAll(',', '')) ?? 0;
    final now = DateTime.now();
    final existing = widget.record;
    final record = MaintenanceRecord(
      id: existing?.id,
      uuid: existing?.uuid,
      syncStatus: existing?.syncStatus ?? MaintenanceRecord.syncStatusPending,
      assetId: widget.asset.id!,
      assetUuid: widget.asset.uuid,
      maintenanceDate: _date,
      description: _description.text.trim(),
      costPaise: (amount * 100).round(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    setState(() => _saving = true);
    try {
      if (existing == null) {
        await widget.repository.insert(record);
      } else {
        await widget.repository.update(record);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      debugPrint('Save maintenance error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save maintenance record.')),
      );
    }
  }

  String _dateText(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.record == null ? 'Add Maintenance' : 'Edit Maintenance'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.record == null
                        ? 'Record maintenance'
                        : 'Update maintenance record',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.asset.name,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 28),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          InkWell(
                            onTap: _saving ? null : _pickDate,
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Maintenance date',
                                border: OutlineInputBorder(),
                                suffixIcon: Icon(Icons.calendar_today_rounded),
                              ),
                              child: Text(_dateText(_date)),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _description,
                            decoration: const InputDecoration(
                              labelText: 'Description *',
                              hintText: 'e.g. Routine servicing and lubrication',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'Description is required'
                                    : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _cost,
                            decoration: const InputDecoration(
                              labelText: 'Cost',
                              prefixText: '₹ ',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            validator: (value) {
                              final text = value?.trim() ?? '';
                              if (text.isEmpty) return null;
                              final amount =
                                  double.tryParse(text.replaceAll(',', ''));
                              return amount == null || amount < 0
                                  ? 'Enter a valid amount'
                                  : null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _notes,
                            decoration: const InputDecoration(
                              labelText: 'Notes',
                              border: OutlineInputBorder(),
                            ),
                            minLines: 4,
                            maxLines: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
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
                      label: Text(_saving ? 'Saving...' : 'Save record'),
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
}
