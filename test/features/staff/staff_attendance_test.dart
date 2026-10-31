import 'package:flutter_test/flutter_test.dart';
import 'package:leo_desk/features/staff/models/staff.dart';

void main() {
  final now = DateTime(2026, 10, 31);

  StaffAttendance attendance({
    required String status,
    String? checkIn,
    String? checkOut,
  }) {
    return StaffAttendance(
      staffId: 1,
      staffUuid: 'staff-1',
      attendanceDate: now,
      status: status,
      checkIn: checkIn,
      checkOut: checkOut,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('full and half day wages use fixed attendance rates', () {
    expect(attendance(status: StaffAttendance.fullDay).baseWagePaise, 15000);
    expect(attendance(status: StaffAttendance.halfDay).baseWagePaise, 7500);
    expect(attendance(status: StaffAttendance.absent).baseWagePaise, 0);
    expect(attendance(status: StaffAttendance.leave).baseWagePaise, 0);
  });

  test('overtime starts only after 4 PM', () {
    expect(
      attendance(status: StaffAttendance.fullDay, checkOut: '16:00').overtimeMinutes,
      0,
    );
    expect(
      attendance(status: StaffAttendance.fullDay, checkOut: '15:30').overtimeMinutes,
      0,
    );
    expect(
      attendance(status: StaffAttendance.fullDay, checkOut: '17:30').overtimeMinutes,
      90,
    );
    expect(
      attendance(
        status: StaffAttendance.fullDay,
        checkIn: '17:00',
        checkOut: '18:00',
      ).overtimeMinutes,
      60,
    );
  });

  test('overtime is paid at ₹37.50 per hour and added to base wage', () {
    final record = attendance(
      status: StaffAttendance.fullDay,
      checkOut: '17:30',
    );
    expect(record.overtimePayPaise, 5625);
    expect(record.totalPayPaise, 20625);
  });

  test('half-day overtime is calculated separately from half-day wage', () {
    final record = attendance(
      status: StaffAttendance.halfDay,
      checkOut: '17:00',
    );
    expect(record.baseWagePaise, 7500);
    expect(record.overtimeMinutes, 60);
    expect(record.overtimePayPaise, 3750);
    expect(record.totalPayPaise, 11250);
  });

  test('absent and leave entries never earn overtime', () {
    expect(
      attendance(status: StaffAttendance.absent, checkOut: '18:00').totalPayPaise,
      0,
    );
    expect(
      attendance(status: StaffAttendance.leave, checkOut: '18:00').totalPayPaise,
      0,
    );
  });
}
