import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../models/expense.dart';

class ExpenseRepository {
  final Database? database;

  ExpenseRepository({this.database});

  Future<Database> get _db async {
    return database ?? await AppDatabase.database;
  }

  Future<int> insert(Expense expense) async {
    final db = await _db;
    final localExpense = expense.copyWith(syncStatus: 'pending');

    return db.insert(
      'expenses',
      localExpense.toMap()..remove('id'),
    );
  }

  Future<int> update(Expense expense) async {
    final db = await _db;
    final localExpense = expense.copyWith(syncStatus: 'pending');

    return db.update(
      'expenses',
      localExpense.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [expense.id],
    );
  }

  /// Marks an expense for deletion. The row is retained until the deletion
  /// has propagated through sync, then it is physically removed.
  Future<int> delete(int id) async {
    final db = await _db;
    return db.update(
      'expenses',
      {
        'sync_status': Expense.syncStatusDeletedPending,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND sync_status != ?',
      whereArgs: [id, Expense.syncStatusDeletedPending],
    );
  }

  Future<Expense?> getById(int id) async {
    final db = await _db;

    final maps = await db.query(
      'expenses',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return Expense.fromMap(maps.first);
  }

  Future<List<Expense>> getAll() async {
    final db = await _db;

    final maps = await db.query(
      'expenses',
      where: 'sync_status != ?',
      whereArgs: [Expense.syncStatusDeletedPending],
      orderBy: 'expense_date DESC, id DESC',
    );

    return maps.map(Expense.fromMap).toList();
  }

  Future<List<Expense>> getPending() async {
    final db = await _db;

    final maps = await db.query(
      'expenses',
      where: 'sync_status IN (?, ?)',
      whereArgs: [
        Expense.syncStatusPending,
        Expense.syncStatusDeletedPending,
      ],
      orderBy: 'expense_date DESC, id DESC',
    );

    return maps.map(Expense.fromMap).toList();
  }

  Future<int> markSynced(String uuid) async {
    final db = await _db;

    return db.update(
      'expenses',
      {'sync_status': Expense.syncStatusSynced},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<int> finalizeDeletion(String uuid) async {
    final db = await _db;
    return db.delete('expenses', where: 'uuid = ?', whereArgs: [uuid]);
  }

  Future<int> applyDeletionFromSync(String uuid) async {
    return finalizeDeletion(uuid);
  }

  Future<int> markDeletedPendingByUuid(String uuid) async {
    final db = await _db;
    return db.update(
      'expenses',
      {
        'sync_status': Expense.syncStatusDeletedPending,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<int> acknowledgeSyncedOrDeleted(String uuid) async {
    final db = await _db;
    final rows = await db.query(
      'expenses',
      columns: ['sync_status'],
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (rows.isEmpty) return 0;

    if (rows.first['sync_status'] == Expense.syncStatusDeletedPending) {
      return db.delete('expenses', where: 'uuid = ?', whereArgs: [uuid]);
    }

    return db.update(
      'expenses',
      {'sync_status': Expense.syncStatusSynced},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<List<Expense>> getAllForSync() async {
    final db = await _db;
    final maps = await db.query(
      'expenses',
      orderBy: 'expense_date DESC, id DESC',
    );
    return maps.map(Expense.fromMap).toList();
  }

  Future<bool> upsertFromSync(
    Expense expense, {
    bool force = false,
  }) async {
    final db = await _db;

    final existing = await db.query(
      'expenses',
      columns: ['id', 'sync_status'],
      where: 'uuid = ?',
      whereArgs: [expense.uuid],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final existingStatus = existing.first['sync_status'];
      if (!force &&
          (existingStatus == Expense.syncStatusPending ||
              existingStatus == Expense.syncStatusDeletedPending)) {
        return false;
      }
    }

    final map = expense.copyWith(syncStatus: 'synced').toMap()..remove('id');

    if (existing.isEmpty) {
      await db.insert('expenses', map);
    } else {
      await db.update(
        'expenses',
        map,
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }

    return true;
  }

  Future<void> deleteAll() async {
    final db = await _db;
    await db.delete('expenses');
  }
}
