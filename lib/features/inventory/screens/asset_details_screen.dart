import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../repositories/asset_repository.dart';
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

  @override
  void initState() {
    super.initState();
    _asset = widget.asset;
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
                              onPressed: null,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add record'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No maintenance records yet.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Maintenance tracking will be added next.',
                          style: Theme.of(context).textTheme.bodyMedium,
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
