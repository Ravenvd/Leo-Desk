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

  test('Windows staff profile remains canonical for an existing UUID', () async {
    final now = DateTime.utc(2026, 11, 1);
    final windows = StaffMember(
      uuid: 'staff-windows-canonical',
      syncStatus: StaffMember.syncStatusPending,
      name: 'Windows Staff',
      role: 'Supervisor',
      joinedOn: now,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('staff', windows.toMap()..remove('id'));

    final canonical = await repository.reconcileStaffFromSync({
      ...windows.toMap(),
      'name': 'Android Edit',
      'role': 'Operator',
    });

    expect(canonical['uuid'], windows.uuid);
    expect(canonical['name'], 'Windows Staff');
    expect(canonical['role'], 'Supervisor');
    expect(canonical['sync_status'], StaffMember.syncStatusPending);
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

  test('Windows attendance UUID and natural key remain canonical', () async {
    final now = DateTime.utc(2026, 11, 2);
    final staff = StaffMember(
      uuid: 'staff-attendance-canonical',
      name: 'Windows Staff',
      joinedOn: now,
      createdAt: now,
      updatedAt: now,
    );
    final staffId = await repository.insertStaff(staff);
    final windowsAttendance = StaffAttendance(
      uuid: 'attendance-windows-canonical',
      syncStatus: StaffMember.syncStatusPending,
      staffId: staffId,
      staffUuid: staff.uuid,
      attendanceDate: now,
      status: StaffAttendance.fullDay,
      checkIn: '09:00',
      checkOut: '16:00',
      notes: 'Windows entry',
      createdAt: now,
      updatedAt: now,
    );
    await db.insert(
      'staff_attendance',
      windowsAttendance.toMap()..remove('id'),
    );

    final sameUuid = await repository.reconcileAttendanceFromSync({
      ...windowsAttendance.toMap(),
      'status': StaffAttendance.absent,
      'notes': 'Android edit',
    });
    expect(sameUuid['uuid'], windowsAttendance.uuid);
    expect(sameUuid['status'], StaffAttendance.fullDay);
    expect(sameUuid['notes'], 'Windows entry');

    final naturalKeyCollision = await repository.reconcileAttendanceFromSync({
      ...windowsAttendance.toMap(),
      'uuid': 'attendance-android-duplicate',
      'status': StaffAttendance.halfDay,
      'notes': 'Android duplicate',
    });
    expect(naturalKeyCollision['uuid'], windowsAttendance.uuid);
    expect(naturalKeyCollision['status'], StaffAttendance.fullDay);
    final rows = await db.query('staff_attendance');
    expect(rows, hasLength(1));
  });

  test('canonical attendance replaces an Android natural-key duplicate', () async {
    final now = DateTime.utc(2026, 11, 3);
    final staff = StaffMember(
      uuid: 'staff-attendance-apply',
      name: 'Test Staff',
      joinedOn: now,
      createdAt: now,
      updatedAt: now,
    );
    final staffId = await repository.insertStaff(staff);
    final android = StaffAttendance(
      uuid: 'attendance-android-copy',
      staffId: staffId,
      staffUuid: staff.uuid,
      attendanceDate: now,
      status: StaffAttendance.absent,
      notes: 'Android local row',
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('staff_attendance', android.toMap()..remove('id'));

    final applied = await repository.upsertAttendanceFromSync({
      ...android.toMap(),
      'uuid': 'attendance-windows-copy',
      'status': StaffAttendance.fullDay,
      'notes': 'Windows canonical row',
      'sync_status': StaffMember.syncStatusPending,
    }, force: true);

    expect(applied, isTrue);
    final rows = await db.query('staff_attendance');
    expect(rows, hasLength(1));
    expect(rows.single['uuid'], 'attendance-windows-copy');
    expect(rows.single['status'], StaffAttendance.fullDay);
    expect(rows.single['notes'], 'Windows canonical row');
    expect(rows.single['sync_status'], StaffMember.syncStatusSynced);
  });

  test('Windows staff payment reconciliation returns canonical UUID record', () async {
    final now = DateTime.utc(2026, 11, 4);
    final staff = StaffMember(
      uuid: 'staff-payment-canonical',
      name: 'Payroll Staff',
      joinedOn: now,
      createdAt: now,
      updatedAt: now,
    );
    final staffId = await repository.insertStaff(staff);
    final payment = StaffPayment(
      uuid: 'payment-windows-canonical',
      syncStatus: StaffPayment.syncStatusPending,
      staffId: staffId,
      staffUuid: staff.uuid,
      periodStart: DateTime.utc(2026, 11, 1),
      periodEnd: DateTime.utc(2026, 11, 30),
      paymentDate: now,
      amountPaise: 125000,
      notes: 'Windows payroll',
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('staff_payments', payment.toMap()..remove('id'));

    final canonical = await repository.reconcilePaymentFromSync({
      ...payment.toMap(),
      'amount_paise': 1,
      'notes': 'Android edit',
    });
    expect(canonical['uuid'], payment.uuid);
    expect(canonical['amount_paise'], 125000);
    expect(canonical['notes'], 'Windows payroll');

    final applied = await repository.upsertPaymentFromSync(canonical, force: true);
    expect(applied, isTrue);
    final rows = await db.query('staff_payments');
    expect(rows, hasLength(1));
    expect(rows.single['amount_paise'], 125000);
    expect(rows.single['staff_id'], staffId);
    expect(rows.single['sync_status'], StaffPayment.syncStatusSynced);
  });
}
