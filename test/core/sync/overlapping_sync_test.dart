import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:leo_desk/core/sync/sync_client.dart';
import 'package:leo_desk/core/sync/sync_manager.dart';

class SlowConnectionClient extends SyncClient {
  SlowConnectionClient()
      : super(
          serverAddress: '127.0.0.1',
          port: 1,
        );

  int connectionChecks = 0;
  final Completer<void> connectionStarted = Completer<void>();
  final Completer<void> releaseConnection = Completer<void>();

  @override
  Future<bool> checkConnection() async {
    connectionChecks++;
    if (!connectionStarted.isCompleted) {
      connectionStarted.complete();
    }
    await releaseConnection.future;
    return false;
  }
}

void main() {
  test('overlapping sync calls share one active sync operation', () async {
    final client = SlowConnectionClient();
    final manager = SyncManager(
      client: client,
      saveLastSyncTime: (_) async {},
    );

    final first = manager.sync();
    await client.connectionStarted.future;

    final second = manager.sync();

    expect(identical(first, second), isTrue);
    expect(client.connectionChecks, 1);

    client.releaseConnection.complete();

    final results = await Future.wait([first, second]);

    expect(results, hasLength(2));
    expect(results[0].connected, isFalse);
    expect(results[1].connected, isFalse);
    expect(client.connectionChecks, 1);

    final third = manager.sync();
    expect(identical(third, first), isFalse);

    await third;
    expect(client.connectionChecks, 2);
  });
}
