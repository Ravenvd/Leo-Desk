import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'database_schema.dart';

class AppDatabase {
  static const _databaseName = 'leo_desk.db';
  static const _databaseVersion = DatabaseSchema.version;

  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _openDatabase();
    return _database!;
  }

  static Future<Database> _openDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, _databaseName);

    return _openAtPath(path);
  }

  static Future<Database> _openAtPath(String path) {
    return openDatabase(
      path,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        for (final statement in DatabaseSchema.createStatements) {
          await db.execute(statement);
        }
      },
    );
  }

  /// Creates an isolated in-memory database for tests.
static Future<Database> openTestDatabase() {
  return openDatabase(
    ':memory:',
    version: _databaseVersion,
    onConfigure: (db) async {
      await db.execute('PRAGMA foreign_keys = ON');
    },
    onCreate: (db, version) async {
      for (final statement in DatabaseSchema.createStatements) {
        await db.execute(statement);
      }
    },
  );
}

  static Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}