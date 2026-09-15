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

  Future<int> delete(int id) async {
    final db = await _db;
    return db.delete(
      'expenses',
      where: 'id = ?',
      whereArgs: [id],
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
      orderBy: 'expense_date DESC, id DESC',
    );

    return maps.map(Expense.fromMap).toList();
  }

  Future<List<Expense>> getPending() async {
    final db = await _db;

    final maps = await db.query(
      'expenses',
      where: 'sync_status = ?',
      whereArgs: ['pending'],
      orderBy: 'expense_date DESC, id DESC',
    );

    return maps.map(Expense.fromMap).toList();
  }

  Future<int> markSynced(String uuid) async {
    final db = await _db;

    return db.update(
      'expenses',
      {'sync_status': 'synced'},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<bool> upsertFromSync(Expense expense) async {
    final db = await _db;

    final existing = await db.query(
      'expenses',
      columns: ['id', 'sync_status'],
      where: 'uuid = ?',
      whereArgs: [expense.uuid],
      limit: 1,
    );

    if (existing.isNotEmpty && existing.first['sync_status'] == 'pending') {
      return false;
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
