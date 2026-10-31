import 'package:uuid/uuid.dart';

class StaffMember {
  static const String syncStatusPending = 'pending';
  static const String syncStatusSynced = 'synced';
  static const String syncStatusDeletedPending = 'deleted_pending';

  final int? id;
  final String uuid;
  final String syncStatus;
  final String name;
  final String? phone;
  final String? role;
  final DateTime joinedOn;
  final bool isActive;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  StaffMember({
    this.id,
    String? uuid,
    this.syncStatus = syncStatusPending,
    required this.name,
    this.phone,
    this.role,
    required this.joinedOn,
    this.isActive = true,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  }) : uuid = uuid ?? const Uuid().v4();

  Map<String, Object?> toMap() => {
        'id': id,
        'uuid': uuid,
        'sync_status': syncStatus,
        'name': name,
        'phone': phone,
        'role': role,
        'joined_on': _dateOnly(joinedOn),
        'is_active': isActive ? 1 : 0,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory StaffMember.fromMap(Map<String, Object?> map) => StaffMember(
        id: map['id'] as int?,
        uuid: map['uuid'] as String,
        syncStatus: map['sync_status'] as String? ?? syncStatusSynced,
        name: map['name'] as String,
        phone: map['phone'] as String?,
        role: map['role'] as String?,
        joinedOn: DateTime.parse(map['joined_on'] as String),
        isActive: (map['is_active'] as int? ?? 1) == 1,
        notes: map['notes'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class StaffAttendance {
  static const String fullDay = 'full_day';
  static const String halfDay = 'half_day';
  static const String absent = 'absent';
  static const String leave = 'leave';

  static const int fullDayWagePaise = 15000;
  static const int halfDayWagePaise = 7500;
  static const int overtimeRatePaisePerHour = 3750;

  final int? id;
  final String uuid;
  final String syncStatus;
  final int staffId;
  final String staffUuid;
  final DateTime attendanceDate;
  final String status;
  final String? checkIn;
  final String? checkOut;
  final String? notes;
  final int baseWagePaise;
  final int overtimeRatePaisePerHour;
  final DateTime createdAt;
  final DateTime updatedAt;

  StaffAttendance({
    this.id,
    String? uuid,
    this.syncStatus = StaffMember.syncStatusPending,
    required this.staffId,
    required this.staffUuid,
    required this.attendanceDate,
    required this.status,
    this.checkIn,
    this.checkOut,
    this.notes,
    int? baseWagePaise,
    this.overtimeRatePaisePerHour = overtimeRatePaisePerHour,
    required this.createdAt,
    required this.updatedAt,
  })  : uuid = uuid ?? const Uuid().v4(),
        baseWagePaise = baseWagePaise ??
            (status == fullDay
                ? fullDayWagePaise
                : status == halfDay
                    ? halfDayWagePaise
                    : 0);

  int get overtimeMinutes {
    if (status != fullDay && status != halfDay) return 0;
    if (checkOut == null) return 0;
    final parts = checkOut!.split(':');
    if (parts.length != 2) return 0;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return 0;
    final checkoutMinutes = hour * 60 + minute;
    return (checkoutMinutes - 16 * 60).clamp(0, 24 * 60);
  }

  int get overtimePayPaise =>
      (overtimeMinutes * overtimeRatePaisePerHour / 60).round();

  int get totalPayPaise => baseWagePaise + overtimePayPaise;

  Map<String, Object?> toMap() => {
        'id': id,
        'uuid': uuid,
        'sync_status': syncStatus,
        'staff_id': staffId,
        'staff_uuid': staffUuid,
        'attendance_date': _dateOnly(attendanceDate),
        'status': status,
        'check_in': checkIn,
        'check_out': checkOut,
        'notes': notes,
        'base_wage_paise': baseWagePaise,
        'overtime_rate_paise_per_hour': overtimeRatePaisePerHour,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory StaffAttendance.fromMap(Map<String, Object?> map) =>
      StaffAttendance(
        id: map['id'] as int?,
        uuid: map['uuid'] as String,
        syncStatus: map['sync_status'] as String? ?? StaffMember.syncStatusSynced,
        staffId: map['staff_id'] as int,
        staffUuid: map['staff_uuid'] as String,
        attendanceDate: DateTime.parse(map['attendance_date'] as String),
        status: map['status'] as String,
        checkIn: map['check_in'] as String?,
        checkOut: map['check_out'] as String?,
        notes: map['notes'] as String?,
        baseWagePaise: map['base_wage_paise'] as int? ?? 0,
        overtimeRatePaisePerHour:
            map['overtime_rate_paise_per_hour'] as int? ?? overtimeRatePaisePerHour,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class StaffPayment {
  static const String syncStatusPending = 'pending';
  static const String syncStatusSynced = 'synced';

  final int? id;
  final String uuid;
  final String syncStatus;
  final int staffId;
  final String staffUuid;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime paymentDate;
  final int amountPaise;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  StaffPayment({
    this.id,
    String? uuid,
    this.syncStatus = syncStatusPending,
    required this.staffId,
    required this.staffUuid,
    required this.periodStart,
    required this.periodEnd,
    required this.paymentDate,
    required this.amountPaise,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  }) : uuid = uuid ?? const Uuid().v4();

  Map<String, Object?> toMap() => {
        'id': id,
        'uuid': uuid,
        'sync_status': syncStatus,
        'staff_id': staffId,
        'staff_uuid': staffUuid,
        'period_start': _dateOnly(periodStart),
        'period_end': _dateOnly(periodEnd),
        'payment_date': _dateOnly(paymentDate),
        'amount_paise': amountPaise,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory StaffPayment.fromMap(Map<String, Object?> map) => StaffPayment(
        id: map['id'] as int?,
        uuid: map['uuid'] as String,
        syncStatus: map['sync_status'] as String? ?? syncStatusSynced,
        staffId: map['staff_id'] as int,
        staffUuid: map['staff_uuid'] as String,
        periodStart: DateTime.parse(map['period_start'] as String),
        periodEnd: DateTime.parse(map['period_end'] as String),
        paymentDate: DateTime.parse(map['payment_date'] as String),
        amountPaise: map['amount_paise'] as int,
        notes: map['notes'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
