import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../models/staff.dart';

class StaffRepository {
  final Database? database;

  StaffRepository({this.database});

  Future<Database> get _db async => database ?? await AppDatabase.database;

  Future<int> insertStaff(StaffMember staff) async {
    final db = await _db;
    return db.insert('staff', staff.toMap()..remove('id'));
  }

  Future<int> updateStaff(StaffMember staff) async {
    final db = await _db;
    return db.update(
      'staff',
      staff.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [staff.id],
    );
  }

  Future<List<StaffMember>> getStaff({bool includeInactive = true}) async {
    final db = await _db;
    final rows = await db.query(
      'staff',
      where: includeInactive ? 'sync_status != ?' : 'is_active = 1 AND sync_status != ?',
      whereArgs: [StaffMember.syncStatusDeletedPending],
      orderBy: 'is_active DESC, name COLLATE NOCASE',
    );
    return rows.map(StaffMember.fromMap).toList();
  }

  Future<StaffMember?> getStaffByUuid(String uuid) async {
    final db = await _db;
    final rows = await db.query(
      'staff',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    return rows.isEmpty ? null : StaffMember.fromMap(rows.first);
  }

  Future<StaffMember?> getStaffById(int id) async {
    final db = await _db;
    final rows = await db.query('staff', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : StaffMember.fromMap(rows.first);
  }

  Future<StaffAttendance?> getAttendance(int staffId, DateTime date) async {
    final db = await _db;
    final rows = await db.query(
      'staff_attendance',
      where: 'staff_id = ? AND attendance_date = ?',
      whereArgs: [staffId, _dateOnly(date)],
      limit: 1,
    );
    return rows.isEmpty ? null : StaffAttendance.fromMap(rows.first);
  }

  Future<List<StaffAttendance>> getAttendanceForDate(DateTime date) async {
    final db = await _db;
    final rows = await db.query(
      'staff_attendance',
      where: 'attendance_date = ?',
      whereArgs: [_dateOnly(date)],
      orderBy: 'staff_id',
    );
    return rows.map(StaffAttendance.fromMap).toList();
  }

  Future<List<StaffAttendance>> getAttendanceForPeriod(
    DateTime start,
    DateTime end,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'staff_attendance',
      where: 'attendance_date >= ? AND attendance_date <= ?',
      whereArgs: [_dateOnly(start), _dateOnly(end)],
      orderBy: 'attendance_date DESC, staff_id',
    );
    return rows.map(StaffAttendance.fromMap).toList();
  }

  Future<int> saveAttendance(StaffAttendance attendance) async {
    final db = await _db;
    final existing = await db.query(
      'staff_attendance',
      columns: ['id', 'uuid', 'created_at'],
      where: 'staff_uuid = ? AND attendance_date = ?',
      whereArgs: [attendance.staffUuid, _dateOnly(attendance.attendanceDate)],
      limit: 1,
    );
    final value = attendance.toMap()
      ..remove('id')
      ..['sync_status'] = StaffMember.syncStatusPending;

    if (existing.isEmpty) return db.insert('staff_attendance', value);

    value['uuid'] = existing.first['uuid'];
    value['created_at'] = existing.first['created_at'];
    return db.update(
      'staff_attendance',
      value,
      where: 'id = ?',
      whereArgs: [existing.first['id']],
    );
  }

  Future<List<StaffPayment>> getPaymentsForPeriod(
    DateTime start,
    DateTime end,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'staff_payments',
      where: 'period_start = ? AND period_end = ?',
      whereArgs: [_dateOnly(start), _dateOnly(end)],
      orderBy: 'payment_date DESC',
    );
    return rows.map(StaffPayment.fromMap).toList();
  }

  Future<int> recordPayment(StaffPayment payment) async {
    final db = await _db;
    return db.insert(
      'staff_payments',
      payment.toMap()..remove('id'),
    );
  }

  Future<List<StaffMember>> getPendingStaff() async {
    final db = await _db;
    final rows = await db.query(
      'staff',
      where: 'sync_status = ?',
      whereArgs: [StaffMember.syncStatusPending],
    );
    return rows.map(StaffMember.fromMap).toList();
  }

  Future<List<StaffAttendance>> getPendingAttendance() async {
    final db = await _db;
    final rows = await db.query(
      'staff_attendance',
      where: 'sync_status = ?',
      whereArgs: [StaffMember.syncStatusPending],
    );
    return rows.map(StaffAttendance.fromMap).toList();
  }

  Future<List<StaffPayment>> getPendingPayments() async {
    final db = await _db;
    final rows = await db.query(
      'staff_payments',
      where: 'sync_status = ?',
      whereArgs: [StaffPayment.syncStatusPending],
    );
    return rows.map(StaffPayment.fromMap).toList();
  }

  Future<List<Map<String, Object?>>> getAllStaffForSync() async {
    final db = await _db;
    return db.query('staff', orderBy: 'created_at');
  }

  Future<List<Map<String, Object?>>> getAllAttendanceForSync() async {
    final db = await _db;
    return db.query('staff_attendance', orderBy: 'attendance_date');
  }

  Future<List<Map<String, Object?>>> getAllPaymentsForSync() async {
    final db = await _db;
    return db.query('staff_payments', orderBy: 'payment_date');
  }

  Future<void> markSynced(String table, String uuid) async {
    final db = await _db;
    await db.update(
      table,
      {'sync_status': StaffMember.syncStatusSynced},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<bool> upsertStaffFromSync(
    Map<String, Object?> record, {
    bool force = false,
  }) async {
    final db = await _db;
    final existing = await db.query(
      'staff',
      columns: ['id', 'sync_status'],
      where: 'uuid = ?',
      whereArgs: [record['uuid']],
      limit: 1,
    );
    if (existing.isNotEmpty &&
        !force &&
        existing.first['sync_status'] == StaffMember.syncStatusPending) {
      return false;
    }
    final value = Map<String, Object?>.from(record)
      ..remove('id')
      ..['sync_status'] = StaffMember.syncStatusSynced;
    if (existing.isEmpty) {
      await db.insert('staff', value);
    } else {
      await db.update('staff', value, where: 'id = ?', whereArgs: [existing.first['id']]);
    }
    return true;
  }

  Future<bool> upsertAttendanceFromSync(
    Map<String, Object?> record, {
    bool force = false,
  }) async {
    final db = await _db;
    final staff = await db.query(
      'staff',
      columns: ['id'],
      where: 'uuid = ?',
      whereArgs: [record['staff_uuid']],
      limit: 1,
    );
    if (staff.isEmpty) return false;
    var existing = await db.query(
      'staff_attendance',
      columns: ['id', 'uuid', 'sync_status'],
      where: 'uuid = ?',
      whereArgs: [record['uuid']],
      limit: 1,
    );
    // One attendance row per staff member per date. If two devices create
    // the same date offline, reconcile by the natural key instead of failing
    // the SQLite UNIQUE constraint.
    if (existing.isEmpty) {
      existing = await db.query(
        'staff_attendance',
        columns: ['id', 'uuid', 'sync_status'],
        where: 'staff_uuid = ? AND attendance_date = ?',
        whereArgs: [record['staff_uuid'], record['attendance_date']],
        limit: 1,
      );
    }
    if (existing.isNotEmpty &&
        !force &&
        existing.first['sync_status'] == StaffMember.syncStatusPending) {
      return false;
    }
    final value = Map<String, Object?>.from(record)
      ..remove('id')
      ..['staff_id'] = staff.first['id']
      ..['sync_status'] = StaffMember.syncStatusSynced;
    if (existing.isEmpty) {
      await db.insert('staff_attendance', value);
    } else {
      await db.update(
        'staff_attendance',
        value,
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
    return true;
  }

  Future<bool> upsertPaymentFromSync(
    Map<String, Object?> record, {
    bool force = false,
  }) async {
    final db = await _db;
    final staff = await db.query(
      'staff',
      columns: ['id'],
      where: 'uuid = ?',
      whereArgs: [record['staff_uuid']],
      limit: 1,
    );
    if (staff.isEmpty) return false;
    final existing = await db.query(
      'staff_payments',
      columns: ['id', 'sync_status'],
      where: 'uuid = ?',
      whereArgs: [record['uuid']],
      limit: 1,
    );
    if (existing.isNotEmpty &&
        !force &&
        existing.first['sync_status'] == StaffPayment.syncStatusPending) {
      return false;
    }
    final value = Map<String, Object?>.from(record)
      ..remove('id')
      ..['staff_id'] = staff.first['id']
      ..['sync_status'] = StaffPayment.syncStatusSynced;
    if (existing.isEmpty) {
      await db.insert('staff_payments', value);
    } else {
      await db.update(
        'staff_payments',
        value,
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
    return true;
  }

  Future<void> deleteAllForSyncReplacement() async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('staff_payments');
      await txn.delete('staff_attendance');
      await txn.delete('staff');
    });
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
