import 'package:flutter_test/flutter_test.dart';
import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/features/staff/models/staff.dart';
import 'package:leo_desk/features/staff/repositories/staff_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late StaffRepository repository;

  setUp(() async {
    db = await AppDatabase.openTestDatabase();
    repository = StaffRepository(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('staff and daily attendance are saved and attendance is unique per date', () async {
    final now = DateTime(2026, 10, 31);
    final staff = StaffMember(
      name: 'Test staff',
      role: 'Embroidery operator',
      joinedOn: now,
      createdAt: now,
      updatedAt: now,
    );
    final staffId = await repository.insertStaff(staff);
    final savedStaff = await repository.getStaffById(staffId);
    expect(savedStaff, isNotNull);

    final first = StaffAttendance(
      staffId: staffId,
      staffUuid: staff.uuid,
      attendanceDate: now,
      status: StaffAttendance.fullDay,
      checkOut: '16:00',
      createdAt: now,
      updatedAt: now,
    );
    await repository.saveAttendance(first);

    final edited = StaffAttendance(
      staffId: staffId,
      staffUuid: staff.uuid,
      attendanceDate: now,
      status: StaffAttendance.halfDay,
      checkOut: '17:00',
      createdAt: now,
      updatedAt: now.add(const Duration(minutes: 1)),
    );
    await repository.saveAttendance(edited);

    final records = await repository.getAttendanceForDate(now);
    expect(records, hasLength(1));
    expect(records.single.status, StaffAttendance.halfDay);
    expect(records.single.overtimePayPaise, 3750);
    expect(records.single.totalPayPaise, 11250);
  });

  test('payroll payments remain separate from earned attendance wages', () async {
    final now = DateTime(2026, 10, 31);
    final staff = StaffMember(
      name: 'Test staff',
      joinedOn: now,
      createdAt: now,
      updatedAt: now,
    );
    final staffId = await repository.insertStaff(staff);
    final payment = StaffPayment(
      staffId: staffId,
      staffUuid: staff.uuid,
      periodStart: DateTime(2026, 10, 1),
      periodEnd: DateTime(2026, 10, 31),
      paymentDate: now,
      amountPaise: 5000,
      notes: 'Advance',
      createdAt: now,
      updatedAt: now,
    );

    await repository.recordPayment(payment);
    final payments = await repository.getPaymentsForPeriod(
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 31),
    );
    expect(payments, hasLength(1));
    expect(payments.single.amountPaise, 5000);
    expect(payments.single.notes, 'Advance');

    final expenses = await db.query(
      'expenses',
      where: 'staff_payment_uuid = ?',
      whereArgs: [payment.uuid],
    );
    expect(expenses, hasLength(1));
    expect(expenses.single['category'], 'Salaries');
    expect(expenses.single['description'], 'Salary – Test staff');
    expect(expenses.single['amount_paise'], 5000);
    expect(expenses.single['expense_date'], now.toIso8601String());
    expect(expenses.single['notes'], 'Advance');
  });

  test('UUID sync preserves pending staff, attendance and payment records', () async {
    final now = DateTime(2026, 11, 1);
    final staff = StaffMember(
      name: 'Local staff name',
      role: 'Operator',
      joinedOn: now,
      createdAt: now,
      updatedAt: now,
    );
    final staffId = await repository.insertStaff(staff);

    final incomingStaff = Map<String, Object?>.from(staff.toMap())
      ..['name'] = 'Stale Windows name';
    expect(await repository.upsertStaffFromSync(incomingStaff), isFalse);
    expect((await repository.getStaffByUuid(staff.uuid))!.name,
        'Local staff name');

    final attendance = StaffAttendance(
      staffId: staffId,
      staffUuid: staff.uuid,
      attendanceDate: now,
      status: StaffAttendance.fullDay,
      createdAt: now,
      updatedAt: now,
    );
    await repository.saveAttendance(attendance);

    final incomingAttendance = Map<String, Object?>.from(attendance.toMap())
      ..['status'] = StaffAttendance.absent;
    expect(
      await repository.upsertAttendanceFromSync(incomingAttendance),
      isFalse,
    );

    final duplicateDateAttendance = Map<String, Object?>.from(
      incomingAttendance,
    )..['uuid'] = 'other-device-attendance';
    expect(
      await repository.upsertAttendanceFromSync(duplicateDateAttendance),
      isFalse,
    );
    final attendanceRows = await db.query(
      'staff_attendance',
      where: 'staff_uuid = ? AND attendance_date = ?',
      whereArgs: [staff.uuid, '2026-11-01'],
    );
    expect(attendanceRows, hasLength(1));
    expect(attendanceRows.single['uuid'], attendance.uuid);
    expect(attendanceRows.single['status'], StaffAttendance.fullDay);

    final payment = StaffPayment(
      staffId: staffId,
      staffUuid: staff.uuid,
      periodStart: DateTime(2026, 11, 1),
      periodEnd: DateTime(2026, 11, 30),
      paymentDate: now,
      amountPaise: 10000,
      notes: 'Local advance',
      createdAt: now,
      updatedAt: now,
    );
    await repository.recordPayment(payment);
    final incomingPayment = Map<String, Object?>.from(payment.toMap())
      ..['amount_paise'] = 20000;
    expect(await repository.upsertPaymentFromSync(incomingPayment), isFalse);
    final savedPayment = await db.query(
      'staff_payments',
      where: 'uuid = ?',
      whereArgs: [payment.uuid],
    );
    expect(savedPayment.single['amount_paise'], 10000);
  });

  test('staff relationships reconcile by UUID across different local IDs', () async {
    final sourceDb = await AppDatabase.openTestDatabase();
    final source = StaffRepository(database: sourceDb);
    final targetDb = await AppDatabase.openTestDatabase();
    final target = StaffRepository(database: targetDb);
    final now = DateTime(2026, 11, 5);

    // Advance the target database's staff AUTOINCREMENT sequence so its
    // local IDs cannot accidentally match the source database's IDs.
    for (var index = 0; index < 3; index++) {
      await target.insertStaff(StaffMember(
        uuid: 'target-only-staff-$index',
        name: 'Target staff $index',
        joinedOn: now,
        createdAt: now,
        updatedAt: now,
      ));
    }

    final sourceStaff = StaffMember(
      uuid: 'shared-staff-uuid',
      name: 'Source operator',
      role: 'Embroidery operator',
      joinedOn: now,
      createdAt: now,
      updatedAt: now,
    );
    final sourceStaffId = await source.insertStaff(sourceStaff);

    final attendance = StaffAttendance(
      uuid: 'shared-attendance-uuid',
      staffId: sourceStaffId,
      staffUuid: sourceStaff.uuid,
      attendanceDate: now,
      status: StaffAttendance.fullDay,
      checkIn: '09:30',
      checkOut: '17:00',
      createdAt: now,
      updatedAt: now,
    );
    await source.saveAttendance(attendance);

    final payment = StaffPayment(
      uuid: 'shared-payment-uuid',
      staffId: sourceStaffId,
      staffUuid: sourceStaff.uuid,
      periodStart: DateTime(2026, 11, 1),
      periodEnd: DateTime(2026, 11, 30),
      paymentDate: now,
      amountPaise: 125000,
      notes: 'November advance',
      createdAt: now,
      updatedAt: now,
    );
    await source.recordPayment(payment);

    // Mimic transport payloads that contain stale/hostile SQLite IDs.
    final staffPayload = Map<String, Object?>.from(sourceStaff.toMap())
      ..['id'] = 9999;
    expect(await target.upsertStaffFromSync(staffPayload), isTrue);

    final importedStaff = await target.getStaffByUuid(sourceStaff.uuid);
    expect(importedStaff, isNotNull);
    expect(importedStaff!.id, isNot(sourceStaffId));
    expect(importedStaff.id, isNot(9999));

    final attendancePayload = Map<String, Object?>.from(attendance.toMap())
      ..['id'] = 9999
      ..['staff_id'] = 9999;
    expect(
      await target.upsertAttendanceFromSync(attendancePayload),
      isTrue,
    );

    final paymentPayload = Map<String, Object?>.from(payment.toMap())
      ..['id'] = 9999
      ..['staff_id'] = 9999;
    expect(await target.upsertPaymentFromSync(paymentPayload), isTrue);

    final attendanceRows = await targetDb.query(
      'staff_attendance',
      where: 'uuid = ?',
      whereArgs: [attendance.uuid],
    );
    expect(attendanceRows, hasLength(1));
    expect(attendanceRows.single['staff_uuid'], sourceStaff.uuid);
    expect(attendanceRows.single['staff_id'], importedStaff.id);
    expect(attendanceRows.single['staff_id'], isNot(9999));

    final paymentRows = await targetDb.query(
      'staff_payments',
      where: 'uuid = ?',
      whereArgs: [payment.uuid],
    );
    expect(paymentRows, hasLength(1));
    expect(paymentRows.single['staff_uuid'], sourceStaff.uuid);
    expect(paymentRows.single['staff_id'], importedStaff.id);
    expect(paymentRows.single['staff_id'], isNot(9999));
    expect(paymentRows.single['amount_paise'], payment.amountPaise);

    await sourceDb.close();
    await targetDb.close();
  });

}
