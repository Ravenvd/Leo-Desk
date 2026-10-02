import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../models/asset.dart';

class AssetRepository {
  final Database? database;

  AssetRepository({this.database});

  Future<Database> get _db async {
    return database ?? await AppDatabase.database;
  }

  Future<int> insert(Asset asset) async {
    final db = await _db;

    return db.transaction((txn) async {
      final localAsset = asset.copyWith(syncStatus: Asset.syncStatusPending);
      final map = localAsset.toMap()..remove('id');

      // Asset codes are generated from SQLite's AUTOINCREMENT id so they
      // remain human-readable and are not reused after an asset is deleted.
      map['asset_code'] = 'PENDING-${localAsset.uuid}';

      final id = await txn.insert('assets', map);
      final assetCode = _formatAssetCode(id);

      await txn.update(
        'assets',
        {'asset_code': assetCode},
        where: 'id = ?',
        whereArgs: [id],
      );

      return id;
    });
  }

  Future<int> update(Asset asset) async {
    if (asset.id == null) {
      throw ArgumentError('Cannot update an asset without an id.');
    }

    final db = await _db;
    final localAsset = asset.copyWith(syncStatus: Asset.syncStatusPending);

    return db.update(
      'assets',
      localAsset.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [asset.id],
    );
  }

  Future<Asset?> getById(int id) async {
    final db = await _db;
    final maps = await db.query(
      'assets',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return Asset.fromMap(maps.first);
  }

  Future<Asset?> getByUuid(String uuid) async {
    final db = await _db;
    final maps = await db.query(
      'assets',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return Asset.fromMap(maps.first);
  }

  Future<List<Asset>> getAll() async {
    final db = await _db;
    final maps = await db.query(
      'assets',
      where: 'sync_status != ?',
      whereArgs: [Asset.syncStatusDeletedPending],
      orderBy: 'name COLLATE NOCASE ASC, id ASC',
    );

    return maps.map(Asset.fromMap).toList();
  }

  Future<List<Asset>> getPending() async {
    final db = await _db;
    final maps = await db.query(
      'assets',
      where: 'sync_status IN (?, ?)',
      whereArgs: [
        Asset.syncStatusPending,
        Asset.syncStatusDeletedPending,
      ],
      orderBy: 'id ASC',
    );

    return maps.map(Asset.fromMap).toList();
  }

  Future<int> markSynced(String uuid) async {
    final db = await _db;
    return db.update(
      'assets',
      {'sync_status': Asset.syncStatusSynced},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<int> delete(int id) async {
    final db = await _db;
    return db.update(
      'assets',
      {
        'sync_status': Asset.syncStatusDeletedPending,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND sync_status != ?',
      whereArgs: [id, Asset.syncStatusDeletedPending],
    );
  }

  Future<int> finalizeDeletion(String uuid) async {
    final db = await _db;
    return db.delete('assets', where: 'uuid = ?', whereArgs: [uuid]);
  }

  Future<bool> upsertFromSync(Asset asset, {bool force = false}) async {
    final db = await _db;

    final existing = await db.query(
      'assets',
      columns: ['id', 'sync_status'],
      where: 'uuid = ?',
      whereArgs: [asset.uuid],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final existingStatus = existing.first['sync_status'];
      if (!force &&
          (existingStatus == Asset.syncStatusPending ||
              existingStatus == Asset.syncStatusDeletedPending)) {
        return false;
      }
    }

    final map = asset.copyWith(syncStatus: Asset.syncStatusSynced).toMap()
      ..remove('id');

    if (existing.isEmpty) {
      await db.insert('assets', map);
    } else {
      await db.update(
        'assets',
        map,
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }

    return true;
  }

  Future<List<Asset>> getAllForSync() async {
    final db = await _db;
    final maps = await db.query('assets', orderBy: 'id ASC');
    return maps.map(Asset.fromMap).toList();
  }

  Future<int> acknowledgeSyncedOrDeleted(String uuid) async {
    final db = await _db;
    final rows = await db.query(
      'assets',
      columns: ['sync_status'],
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (rows.isEmpty) return 0;

    if (rows.first['sync_status'] == Asset.syncStatusDeletedPending) {
      return db.delete('assets', where: 'uuid = ?', whereArgs: [uuid]);
    }

    return db.update(
      'assets',
      {'sync_status': Asset.syncStatusSynced},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<void> deleteAll() async {
    final db = await _db;
    await db.delete('assets');
  }

  String _formatAssetCode(int id) {
    return 'AST-${id.toString().padLeft(4, '0')}';
  }
}
