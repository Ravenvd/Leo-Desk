import 'package:flutter/material.dart';

import '../../../core/sync/sync_events.dart';
import '../models/asset.dart';
import '../repositories/asset_repository.dart';

class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key, required this.repository});
  final AssetRepository repository;

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  List<Asset> _assets = [];
  bool _isLoading = true;
  String? _error;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _loadAssets();
    syncCompleted.addListener(_onSyncCompleted);
  }

  @override
  void dispose() {
    syncCompleted.removeListener(_onSyncCompleted);
    super.dispose();
  }

  void _onSyncCompleted() {
    if (mounted) _loadAssets();
  }

  Future<void> _loadAssets() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final assets = await widget.repository.getAll();
      if (!mounted) return;
      setState(() { _assets = assets; _isLoading = false; });
    } catch (error, stackTrace) {
      debugPrint('Load assets error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() { _error = 'Unable to load assets.'; _isLoading = false; });
    }
  }

  List<Asset> get _filteredAssets =>
      _statusFilter == null ? _assets : _assets.where((asset) => asset.status == _statusFilter).toList();

  @override
  Widget build(BuildContext context) {
    final assets = _filteredAssets;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back to inventory',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Assets', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text('${_assets.length} ${_assets.length == 1 ? 'asset' : 'assets'}', style: Theme.of(context).textTheme.bodyLarge),
                    ],
                  ),
                ),
                OutlinedButton.icon(onPressed: _loadAssets, icon: const Icon(Icons.refresh_rounded), label: const Text('Refresh')),
              ],
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(label: const Text('All'), selected: _statusFilter == null, onSelected: (_) => setState(() => _statusFilter = null)),
                ...Asset.statuses.map((status) => FilterChip(
                  label: Text(status),
                  selected: _statusFilter == status,
                  onSelected: (_) => setState(() => _statusFilter = _statusFilter == status ? null : status),
                )),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(child: _buildContent(assets)),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildContent(List<Asset> assets) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!),
        const SizedBox(height: 12),
        FilledButton(onPressed: _loadAssets, child: const Text('Retry')),
      ]));
    }
    if (assets.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.precision_manufacturing_outlined, size: 56),
        const SizedBox(height: 16),
        Text(_statusFilter == null ? 'No assets yet' : 'No assets with this status', style: Theme.of(context).textTheme.titleMedium),
        if (_statusFilter == null) ...[
          const SizedBox(height: 8),
          const Text('Asset creation will be added in the next step.'),
        ],
      ]));
    }
    return ListView.separated(
      itemCount: assets.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _AssetTile(asset: assets[index]),
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({required this.asset});
  final Asset asset;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: CircleAvatar(child: Icon(_iconForStatus(asset.status))),
        title: Text(asset.name),
        subtitle: Text('${asset.assetCode} • ${asset.manufacturerModel ?? 'Manufacturer/model not specified'}'),
        trailing: Chip(label: Text(asset.status)),
      ),
    );
  }

  IconData _iconForStatus(String status) {
    switch (status) {
      case Asset.statusMaintenance: return Icons.build_rounded;
      case Asset.statusInactive: return Icons.pause_circle_outline_rounded;
      case Asset.statusCondemned: return Icons.block_rounded;
      default: return Icons.precision_manufacturing_rounded;
    }
  }
}
