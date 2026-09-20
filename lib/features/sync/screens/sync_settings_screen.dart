import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/sync/sync_config.dart';
import '../../../core/sync/sync_events.dart';
import '../../../core/sync/sync_manager.dart';
import '../../../core/sync/sync_server.dart';

class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key, this.syncServer});

  /// Present only on Windows, where this device hosts the server.
  final SyncServer? syncServer;

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController();

  String? _statusMessage;
  DateTime? _lastSyncAt;
  List<String> _localAddresses = [];
  bool _isSyncing = false;

  bool get _isHost => Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await SyncConfig.load();
    final lastSync = await SyncConfig.loadLastSyncTime();

    var addresses = <String>[];
    if (_isHost) {
      addresses = await _findLocalAddresses();
    }

    if (!mounted) return;

    setState(() {
      _hostController.text = config.serverHost ?? '';
      _portController.text = config.serverPort.toString();
      _lastSyncAt = lastSync;
      _localAddresses = addresses;
    });
  }

  Future<List<String>> _findLocalAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      return [
        for (final interface in interfaces)
          for (final address in interface.addresses)
            if (!address.isLoopback) address.address,
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _save() async {
    final port =
        int.tryParse(_portController.text.trim()) ?? SyncConfig.defaultPort;

    final config = SyncConfig(
      serverHost: _hostController.text.trim(),
      serverPort: port,
    );
    await config.save();

    if (!mounted) return;
    setState(() {
      _statusMessage = 'Settings saved.';
    });
  }

  Future<void> _syncNow() async {
    setState(() {
      _isSyncing = true;
      _statusMessage = null;
    });

    try {
      final config = await SyncConfig.load();
      if (!config.isConfigured) {
        if (!mounted) return;
        setState(() {
          _statusMessage = 'Save the Windows server address first.';
        });
        return;
      }

      final result = await SyncManager.fromConfig(config).sync();

      if (!mounted) return;

      if (result.connected) {
        notifySyncCompleted();
        setState(() {
          _lastSyncAt = result.syncedAt;
          _statusMessage = result.totalSynced == 0
              ? 'Already up to date.'
              : 'Sync complete. ${result.totalSynced} records exchanged.';
        });
      } else {
        setState(() {
          _statusMessage = 'Could not reach the Windows server.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Sync failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Settings',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 28),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: _isHost ? _buildHostCard() : _buildClientCard(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHostCard() {
    final running = widget.syncServer?.isRunning ?? false;
    final port = widget.syncServer?.port ?? SyncConfig.defaultPort;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Network Sync', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'This device is the sync server. Android devices connect '
              'to it over Wi-Fi.',
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _StatusDot(color: running ? Colors.green : Colors.red),
                const SizedBox(width: 8),
                Text(
                  running
                      ? 'Server running on port $port'
                      : 'Server not running',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            if (_localAddresses.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Enter one of these addresses on your Android device:',
              ),
              const SizedBox(height: 8),
              for (final address in _localAddresses)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: SelectableText(
                    address,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildClientCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Network Sync', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Connect to the Windows computer running Leo Desk. '
              'Both devices must be on the same Wi-Fi network. '
              'Sync runs automatically on startup, when Wi-Fi connects, '
              'and every 10 minutes.',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: 'Server address (IP)',
                hintText: 'e.g. 192.168.1.10',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: 'Port',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: _save,
              child: const Text('Save Settings'),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'Sync',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Sync changes with the Windows computer now. Pulled records are '
              'acknowledged on Windows after they are successfully applied '
              'on this device.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isSyncing ? null : _syncNow,
              icon: _isSyncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(_isSyncing ? 'Syncing…' : 'Sync Now'),
            ),
            const SizedBox(height: 20),
            if (_lastSyncAt != null)
              Text(
                'Last synced: ${_formatTime(_lastSyncAt!)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _statusMessage!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.day}/${local.month}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
