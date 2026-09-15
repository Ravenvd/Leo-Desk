import 'package:shared_preferences/shared_preferences.dart';

/// Configuration for LAN synchronisation between the Windows host
/// (source of truth, runs the HTTP server) and Android clients.
class SyncConfig {
  static const int defaultPort = 8080;
  static const String defaultToken = 'leo-desk-sync-v1';

  static const _hostKey = 'sync_server_host';
  static const _portKey = 'sync_server_port';
  static const _lastSyncKey = 'sync_last_sync_at';

  /// Hostname or IP of the Windows machine running the sync server.
  /// Only used on Android clients; null means "not configured".
  final String? serverHost;

  /// Port the sync server listens on (both sides).
  final int serverPort;

  /// Shared secret sent in the X-Leo-Sync-Token header.
  final String token;

  const SyncConfig({
    this.serverHost,
    this.serverPort = defaultPort,
    this.token = defaultToken,
  });

  bool get isConfigured => serverHost != null && serverHost!.trim().isNotEmpty;

  SyncConfig copyWith({String? serverHost, int? serverPort, String? token}) {
    return SyncConfig(
      serverHost: serverHost ?? this.serverHost,
      serverPort: serverPort ?? this.serverPort,
      token: token ?? this.token,
    );
  }

  static Future<SyncConfig> load() async {
    final prefs = await SharedPreferences.getInstance();

    return SyncConfig(
      serverHost: prefs.getString(_hostKey),
      serverPort: prefs.getInt(_portKey) ?? defaultPort,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();

    if (serverHost == null || serverHost!.trim().isEmpty) {
      await prefs.remove(_hostKey);
    } else {
      await prefs.setString(_hostKey, serverHost!.trim());
    }
    await prefs.setInt(_portKey, serverPort);
  }

  static Future<DateTime?> loadLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastSyncKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  static Future<void> saveLastSyncTime(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, time.toIso8601String());
  }
}
