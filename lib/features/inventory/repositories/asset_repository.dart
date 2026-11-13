import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../models/asset.dart';

class AssetRepository {
  final Database? database;
  final bool isNumberAuthority;

  /// Windows owns canonical asset-code allocation. Android stores a UUID-based
  /// placeholder until the Windows host assigns and returns the real code.
  AssetRepository({this.database, bool? isNumberAuthority})
      : isNumberAuthority = isNumberAuthority ?? Platform.isWindows;

  Future<Database> get _db async {
    return database ?? await AppDatabase.database;
  }

  Future<int> insert(Asset asset) async {
    final db = await _db;

    return db.transaction((txn) async {
      final localAsset = asset.copyWith(syncStatus: Asset.syncStatusPending);
      final map = localAsset.toMap()..remove('id');

      // Never derive a canonical suffix on Android. Its local SQLite ID is
      // unrelated to the Windows database and can collide with another device.
      // Windows may safely use its own AUTOINCREMENT sequence as the authority.
      map['asset_code'] = isNumberAuthority
          ? ''
          : 'PENDING-${localAsset.uuid}';

      final id = await txn.insert('assets', map);
      if (isNumberAuthority) {
        await txn.update(
          'assets',
          {'asset_code': _formatAssetCode(id)},
          where: 'id = ?',
          whereArgs: [id],
        );
      }

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

  Future<int> markDeletedPendingByUuid(String uuid) async {
    final db = await _db;
    return db.update('assets', {'sync_status': Asset.syncStatusDeletedPending, 'updated_at': DateTime.now().toIso8601String()}, where: 'uuid = ?', whereArgs: [uuid]);
  }

  Future<int> applyDeletionFromSync(String uuid) => finalizeDeletion(uuid);

  Future<int> finalizeDeletion(String uuid) async {
    final db = await _db;
    return db.delete('assets', where: 'uuid = ?', whereArgs: [uuid]);
  }

  Future<bool> upsertFromSync(Asset asset, {bool force = false}) async {
    final db = await _db;

    final existing = await db.query(
      'assets',
      columns: ['id', 'sync_status', 'asset_code'],
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

    // Windows never accepts a client-proposed number for a new UUID. Its
    // AUTOINCREMENT row ID supplies a monotonic sequence that survives deletes.
    // For an existing UUID, retain the already assigned Windows code.
    var reconciledAsset = asset;
    if (isNumberAuthority) {
      reconciledAsset = asset.copyWith(
        assetCode: existing.isEmpty
            ? 'PENDING-${asset.uuid}'
            : existing.first['asset_code'] as String,
      );
    }

    final map = reconciledAsset
        .copyWith(syncStatus: Asset.syncStatusSynced)
        .toMap()
      ..remove('id');

    await db.transaction((txn) async {
      if (!isNumberAuthority) {
        // Older Android installs may still have locally generated AST codes.
        // Free a colliding value before applying the Windows canonical code.
        final codeOwner = await txn.query(
          'assets',
          columns: ['id', 'uuid'],
          where: 'asset_code = ? AND uuid != ?',
          whereArgs: [reconciledAsset.assetCode, reconciledAsset.uuid],
          limit: 1,
        );
        if (codeOwner.isNotEmpty) {
          await txn.update(
            'assets',
            {'asset_code': 'PENDING-${codeOwner.first['uuid']}'},
            where: 'id = ?',
            whereArgs: [codeOwner.first['id']],
          );
        }
      }

      if (existing.isEmpty) {
        final insertedId = await txn.insert('assets', map);
        if (isNumberAuthority) {
          await txn.update(
            'assets',
            {'asset_code': _formatAssetCode(insertedId)},
            where: 'id = ?',
            whereArgs: [insertedId],
          );
        }
      } else {
        await txn.update(
          'assets',
          map,
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      }
    });

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
