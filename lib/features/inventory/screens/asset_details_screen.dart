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
      if (refreshed != null) {
        setState(() => _asset = refreshed);
      }
    }
  }

  Future<void> _changeStatus() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Change asset status'),
        children: Asset.statuses
            .map(
              (status) => SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(status),
                child: Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 10,
                      color: _statusColorFor(status),
                    ),
                    const SizedBox(width: 12),
                    Text(status),
                    if (status == _asset.status) ...[
                      const Spacer(),
                      const Icon(Icons.check_rounded),
                    ],
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );

    if (selected == null || selected == _asset.status || !mounted) return;

    if (selected == Asset.statusCondemned) {
      await _condemnAsset();
      return;
    }

    await _saveStatus(selected);
  }

  Future<void> _condemnAsset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Condemn asset?'),
        content: const Text(
          'This marks the asset as Condemned. The asset and its maintenance '
          'history will be preserved for records, but it will no longer be '
          'treated as an active asset.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Condemn asset'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _saveStatus(Asset.statusCondemned);
  }

  Future<void> _saveStatus(String status) async {
    try {
      await widget.repository.update(_asset.copyWith(status: status));
      final refreshed = await widget.repository.getByUuid(_asset.uuid);
      if (refreshed != null && mounted) {
        setState(() => _asset = refreshed);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Asset status changed to $status.')),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Update asset status error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to update asset status.')),
      );
    }
  }

  Color _statusColorFor(String status) {
    switch (status) {
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

  Color _statusColor(BuildContext context) => _statusColorFor(_asset.status);

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
    final totalMaintenanceCostPaise = _maintenance.fold<int>(
      0,
      (total, record) => total + record.costPaise,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Asset Details'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Asset actions',
            onSelected: (value) {
              if (value == 'status') {
                _changeStatus();
              } else if (value == 'condemn') {
                _condemnAsset();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'status',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.swap_vert_rounded),
                  title: Text('Change status'),
                ),
              ),
              if (_asset.status != Asset.statusCondemned)
                PopupMenuItem(
                  value: 'condemn',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.block_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text('Condemn asset'),
                  ),
                ),
            ],
          ),
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
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Chip(
                                    avatar: Icon(
                                      Icons.circle,
                                      size: 10,
                                      color: statusColor,
                                    ),
                                    label: Text(_asset.status),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _changeStatus,
                                    icon: const Icon(Icons.swap_vert_rounded),
                                    label: const Text('Change status'),
                                  ),
                                ],
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
