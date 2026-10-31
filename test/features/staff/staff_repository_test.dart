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
}
