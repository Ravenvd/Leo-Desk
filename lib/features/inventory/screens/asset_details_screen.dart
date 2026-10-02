import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../repositories/asset_repository.dart';
import '../models/maintenance_record.dart';
import '../repositories/maintenance_repository.dart';
import 'maintenance_form_screen.dart';
import 'asset_form_screen.dart';

class AssetDetailsScreen extends StatefulWidget {
  const AssetDetailsScreen({
    super.key,
    required this.repository,
    required this.asset,
  });

  final AssetRepository repository;
  final Asset asset;

  @override
  State<AssetDetailsScreen> createState() => _AssetDetailsScreenState();
}

class _AssetDetailsScreenState extends State<AssetDetailsScreen> {
  late Asset _asset;
  final _maintenanceRepository = MaintenanceRepository();
  List<MaintenanceRecord> _maintenance = [];
  bool _maintenanceLoading = true;

  @override
  void initState() {
    super.initState();
    _asset = widget.asset;
    _loadMaintenance();
  }

  Future<void> _loadMaintenance() async {
    if (_asset.id == null) return;
    setState(() => _maintenanceLoading = true);
    final records = await _maintenanceRepository.getForAsset(_asset.id!);
    if (mounted) setState(() { _maintenance = records; _maintenanceLoading = false; });
  }

  Future<void> _addMaintenance() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MaintenanceFormScreen(
          repository: _maintenanceRepository,
          asset: _asset,
        ),
      ),
    );
    if (saved == true && mounted) await _loadMaintenance();
  }

  Future<void> _editMaintenance(MaintenanceRecord record) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MaintenanceFormScreen(
          repository: _maintenanceRepository,
          asset: _asset,
          record: record,
        ),
      ),
    );
    if (saved == true && mounted) await _loadMaintenance();
  }

  Future<void> _edit() async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AssetFormScreen(
          repository: widget.repository,
          asset: _asset,
        ),
      ),
    );

    if (updated == true && mounted) {
      final refreshed = await widget.repository.getByUuid(_asset.uuid);
      if (refreshed != null) setState(() => _asset = refreshed);
    }
  }

  Color _statusColor(BuildContext context) {
    switch (_asset.status) {
      case Asset.statusMaintenance:
        return Theme.of(context).colorScheme.tertiary;
      case Asset.statusInactive:
        return Theme.of(context).colorScheme.outline;
      case Asset.statusCondemned:
        return Theme.of(context).colorScheme.error;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not specified';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatCurrency(int? paise) {
    if (paise == null) return 'Not specified';
    return '₹${(paise / 100).toStringAsFixed(2)}';
  }

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Asset Details'),
        actions: [
          IconButton(
            tooltip: 'Edit asset',
            onPressed: _edit,
            icon: const Icon(Icons.edit_rounded),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 30,
                          child: Icon(
                            Icons.precision_manufacturing_rounded,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _asset.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                _asset.assetCode,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 14),
                              Chip(
                                avatar: Icon(
                                  Icons.circle,
                                  size: 10,
                                  color: statusColor,
                                ),
                                label: Text(_asset.status),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Asset information',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 24),
                        _info('Purchase date', _formatDate(_asset.purchaseDate)),
                        _info('Purchase cost', _formatCurrency(_asset.purchaseCostPaise)),
                        _info(
                          'Manufacturer / Model',
                          _asset.manufacturerModel ?? 'Not specified',
                        ),
                        _info(
                          'Serial number',
                          _asset.serialNumber ?? 'Not specified',
                        ),
                        _info(
                          'Warranty',
                          _asset.warrantyInformation ?? 'Not specified',
                        ),
                        _info(
                          'Notes',
                          _asset.notes ?? 'No notes',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Maintenance',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _addMaintenance,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add record'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_maintenanceLoading)
                          const Center(child: CircularProgressIndicator())
                        else if (_maintenance.isEmpty)
                          Text(
                            'No maintenance records yet.',
                            style: Theme.of(context).textTheme.bodyLarge,
                          )
                        else
                          ..._maintenance.map(
                            (record) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Card(
                                margin: EdgeInsets.zero,
                                child: ListTile(
                                  onTap: () => _editMaintenance(record),
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.build_rounded),
                                  ),
                                  title: Text(record.description),
                                  subtitle: Text(
                                    '${_formatDate(record.maintenanceDate)} • '
                                    '${_formatCurrency(record.costPaise)}'
                                    '${record.notes == null ? '' : ' • ${record.notes}'}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: const Icon(Icons.chevron_right_rounded),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
