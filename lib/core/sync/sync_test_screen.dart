import 'package:flutter/material.dart';

import 'sync_client.dart';

class SyncTestScreen extends StatefulWidget {
  const SyncTestScreen({
    super.key,
    required this.serverAddress,
  });

  final String serverAddress;

  @override
  State<SyncTestScreen> createState() => _SyncTestScreenState();
}

class _SyncTestScreenState extends State<SyncTestScreen> {
  bool _isChecking = false;
  bool? _connected;

  Future<void> _checkConnection() async {
    setState(() {
      _isChecking = true;
      _connected = null;
    });

    final client = SyncClient(
      serverAddress: widget.serverAddress,
    );

    final connected = await client.checkConnection();

    if (!mounted) {
      return;
    }

    setState(() {
      _isChecking = false;
      _connected = connected;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Test'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.sync_rounded,
                size: 64,
              ),
              const SizedBox(height: 24),
              const Text(
                'Windows Server Connection',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                widget.serverAddress,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              if (_connected == true)
                const Text(
                  'Connected ✓',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else if (_connected == false)
                const Text(
                  'Connection failed',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isChecking ? null : _checkConnection,
                icon: _isChecking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.wifi_rounded),
                label: Text(
                  _isChecking ? 'Checking...' : 'Check Connection',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}