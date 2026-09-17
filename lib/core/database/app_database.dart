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
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          for (final statement in DatabaseSchema.upgradeToVersion3) {
            await db.execute(statement);
          }
        }
        if (oldVersion < 4) {
          await DatabaseSchema.upgradeToVersion4(db);
        }
        if (oldVersion < 5) {
          await DatabaseSchema.upgradeToVersion5(db);
        }
        if (oldVersion < 6) {
          await DatabaseSchema.upgradeToVersion6(db);
        }
        if (oldVersion < 7) {
          await DatabaseSchema.upgradeToVersion7(db);
        }
        if (oldVersion < 8) {
          await DatabaseSchema.upgradeToVersion8(db);
        }
      },
    );
  }

  /// Creates an isolated database for tests. Uses an in-memory database
  /// unless [path] is given — pass distinct file paths when a test needs
  /// two independent databases (in-memory handles are shared per process).
  static Future<Database> openTestDatabase({String? path}) {
    return openDatabase(
      path ?? inMemoryDatabasePath,
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
