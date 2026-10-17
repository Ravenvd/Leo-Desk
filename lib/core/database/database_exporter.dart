import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Creates a consistent SQLite snapshot and lets the user choose where to save it.
class DatabaseExporter {
  static const _channel = MethodChannel('leo_desk/database_export');

  static Future<void> exportToUserSelectedFile() async {
    final Database database = await AppDatabase.database;
    final temporaryDirectory = await getTemporaryDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final backupPath = p.join(
      temporaryDirectory.path,
      'leo_desk_backup_$timestamp.db',
    );
    final escapedPath = backupPath.replaceAll("'", "''");

    try {
      // VACUUM INTO creates a standalone, transactionally consistent SQLite
      // snapshot, including committed changes that may be in the WAL file.
      await database.execute("VACUUM INTO '$escapedPath'");
      final saved = await _channel.invokeMethod<bool>(
        'saveDatabaseFile',
        <String, Object>{
          'path': backupPath,
          'fileName': 'leo_desk_backup_$timestamp.db',
        },
      );

      if (saved != true) {
        throw PlatformException(
          code: 'export_cancelled',
          message: 'No destination was selected for the database export.',
        );
      }
    } finally {
      final backup = File(backupPath);
      if (await backup.exists()) {
        await backup.delete();
      }
    }
  }
}
