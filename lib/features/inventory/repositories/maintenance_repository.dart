import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../models/maintenance_record.dart';

class MaintenanceRepository {
  final Database? database;

  MaintenanceRepository({this.database});

  Future<Database> get _db async =>
      database ?? await AppDatabase.database;

  Future<int> insert(MaintenanceRecord record) async {
    final db = await _db;
    return db.insert(
      'maintenance_records',
      record.copyWith(syncStatus: MaintenanceRecord.syncStatusPending)
          .toMap()
        ..remove('id'),
    );
  }

  Future<int> update(MaintenanceRecord record) async {
    if (record.id == null) {
      throw ArgumentError('Cannot update maintenance without an id.');
    }
    final db = await _db;
    return db.update(
      'maintenance_records',
      record.copyWith(syncStatus: MaintenanceRecord.syncStatusPending)
          .toMap()
        ..remove('id'),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  Future<List<MaintenanceRecord>> getForAsset(int assetId) async {
    final db = await _db;
    final maps = await db.query(
      'maintenance_records',
      where: 'asset_id = ? AND sync_status != ?',
      whereArgs: [assetId, MaintenanceRecord.syncStatusDeletedPending],
      orderBy: 'maintenance_date DESC, id DESC',
    );
    return maps.map(MaintenanceRecord.fromMap).toList();
  }

  Future<MaintenanceRecord?> getById(int id) async {
    final db = await _db;
    final maps = await db.query(
      'maintenance_records',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return MaintenanceRecord.fromMap(maps.first);
  }

  Future<int> delete(int id) async {
    final db = await _db;
    return db.update(
      'maintenance_records',
      {
        'sync_status': MaintenanceRecord.syncStatusDeletedPending,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND sync_status != ?',
      whereArgs: [id, MaintenanceRecord.syncStatusDeletedPending],
    );
  }

  Future<List<MaintenanceRecord>> getPending() async {
    final db = await _db;
    final maps = await db.query(
      'maintenance_records',
      where: 'sync_status IN (?, ?)',
      whereArgs: [
        MaintenanceRecord.syncStatusPending,
        MaintenanceRecord.syncStatusDeletedPending,
      ],
      orderBy: 'id ASC',
    );
    return maps.map(MaintenanceRecord.fromMap).toList();
  }

  Future<int> acknowledgeSyncedOrDeleted(String uuid) async {
    final db = await _db;
    final rows = await db.query(
      'maintenance_records',
      columns: ['sync_status'],
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (rows.isEmpty) return 0;

    if (rows.first['sync_status'] ==
        MaintenanceRecord.syncStatusDeletedPending) {
      return db.delete(
        'maintenance_records',
        where: 'uuid = ?',
        whereArgs: [uuid],
      );
    }

    return db.update(
      'maintenance_records',
      {'sync_status': MaintenanceRecord.syncStatusSynced},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }
}
