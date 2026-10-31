import 'package:flutter/material.dart';

import '../models/staff.dart';
import '../repositories/staff_repository.dart';

class StaffManagerScreen extends StatefulWidget {
  const StaffManagerScreen({super.key, required this.repository});

  final StaffRepository repository;

  @override
  State<StaffManagerScreen> createState() => _StaffManagerScreenState();
}

class _StaffManagerScreenState extends State<StaffManagerScreen> {
  DateTime _selectedDate = DateTime.now();
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<List<StaffMember>> _staffFuture;
  late Future<List<StaffAttendance>> _attendanceFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _staffFuture = widget.repository.getStaff();
    _attendanceFuture = widget.repository.getAttendanceForDate(_selectedDate);
  }

  Future<void> _selectAttendanceDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) {
      setState(() {
        _selectedDate = date;
        _refresh();
      });
    }
  }

  Future<void> _selectPayrollMonth() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Choose a date in the payroll month',
    );
    if (date != null && mounted) {
      setState(() {
        _selectedMonth = DateTime(date.year, date.month);
      });
    }
  }

  Future<void> _addStaff() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _StaffDialog(repository: widget.repository),
    );
    if (saved == true && mounted) setState(_refresh);
  }

  Future<void> _editStaff(StaffMember staff) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _StaffDialog(repository: widget.repository, staff: staff),
    );
    if (saved == true && mounted) setState(_refresh);
  }

  Future<void> _markAttendance(
    StaffMember staff,
    StaffAttendance? attendance,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AttendanceDialog(
        repository: widget.repository,
        staff: staff,
        date: _selectedDate,
        attendance: attendance,
      ),
    );
    if (saved == true && mounted) {
      setState(_refresh);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Staff Manager'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.people_alt_outlined), text: 'Staff'),
              Tab(icon: Icon(Icons.fact_check_outlined), text: 'Attendance'),
              Tab(icon: Icon(Icons.account_balance_wallet_outlined), text: 'Payroll'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildStaffTab(),
            _buildAttendanceTab(),
            _buildPayrollTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffTab() {
    return FutureBuilder<List<StaffMember>>(
      future: _staffFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Could not load staff: ${snapshot.error}'));
        }
        final staff = snapshot.data ?? [];
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Staff members',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _addStaff,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Add staff'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: staff.isEmpty
                  ? const Center(
                      child: Text('No staff added yet. Add your first staff member.'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: staff.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final member = staff[index];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text(member.name.isEmpty
                                  ? '?'
                                  : member.name.substring(0, 1).toUpperCase()),
                            ),
                            title: Text(member.name),
                            subtitle: Text([
                              if (member.role?.isNotEmpty == true) member.role!,
                              if (member.phone?.isNotEmpty == true) member.phone!,
                              member.isActive ? 'Active' : 'Inactive',
                            ].join(' • ')),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _editStaff(member),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAttendanceTab() {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([_staffFuture, _attendanceFuture]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Could not load attendance: ${snapshot.error}'));
        }
        final staff = snapshot.data![0] as List<StaffMember>;
        final records = snapshot.data![1] as List<StaffAttendance>;
        final attendanceByStaff = {
          for (final record in records) record.staffUuid: record,
        };
        final activeStaff = staff.where((member) => member.isActive).toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Daily attendance',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _selectAttendanceDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(_formatDate(_selectedDate)),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('10:00 AM – 4:00 PM  •  Full day ₹150  •  Half day ₹75'),
              ),
            ),
            Expanded(
              child: activeStaff.isEmpty
                  ? const Center(child: Text('Add active staff members to record attendance.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: activeStaff.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final member = activeStaff[index];
                        final record = attendanceByStaff[member.uuid];
                        return Card(
                          child: ListTile(
                            title: Text(member.name),
                            subtitle: Text(record == null
                                ? 'Not marked'
                                : '${_statusLabel(record.status)} • Base ₹${(record.baseWagePaise / 100).toStringAsFixed(2)}'
                                    '${record.overtimeMinutes > 0 ? ' • OT ${_formatDuration(record.overtimeMinutes)} (+₹${(record.overtimePayPaise / 100).toStringAsFixed(2)})' : ''}'),
                            trailing: FilledButton.tonal(
                              onPressed: () => _markAttendance(member, record),
                              child: Text(record == null ? 'Mark' : 'Edit'),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPayrollTab() {
    final start = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final end = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        widget.repository.getStaff(),
        widget.repository.getAttendanceForPeriod(start, end),
        widget.repository.getPaymentsForPeriod(start, end),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Could not load payroll: ${snapshot.error}'));
        }
        final staff = snapshot.data![0] as List<StaffMember>;
        final attendance = snapshot.data![1] as List<StaffAttendance>;
        final payments = snapshot.data![2] as List<StaffPayment>;
        var grandEarned = 0;
        var grandPaid = 0;
        final summaries = <Widget>[];
        for (final member in staff) {
          final records = attendance.where((item) => item.staffUuid == member.uuid).toList();
          final memberPayments = payments.where((item) => item.staffUuid == member.uuid);
          final earned = records.fold<int>(0, (sum, item) => sum + item.totalPayPaise);
          final paid = memberPayments.fold<int>(0, (sum, item) => sum + item.amountPaise);
          final due = earned - paid;
          grandEarned += earned;
          grandPaid += paid;
          summaries.add(
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(member.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        _PayrollMetric(label: 'Days', value: '${records.where((r) => r.status == StaffAttendance.fullDay).length} full / ${records.where((r) => r.status == StaffAttendance.halfDay).length} half'),
                        _PayrollMetric(label: 'Overtime', value: _formatDuration(records.fold<int>(0, (sum, r) => sum + r.overtimeMinutes))),
                        _PayrollMetric(label: 'Earned', value: _money(earned)),
                        _PayrollMetric(label: 'Paid', value: _money(paid)),
                        _PayrollMetric(label: 'Balance', value: _money(due)),
                      ],
                    ),
                    if (due > 0) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonal(
                          onPressed: () => _recordPayment(member, start, end, due),
                          child: const Text('Record payment'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Expanded(child: Text('Monthly payroll', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
                  OutlinedButton.icon(
                    onPressed: _selectPayrollMonth,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(_monthLabel(_selectedMonth)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    children: [
                      _PayrollMetric(label: 'Total earned', value: _money(grandEarned)),
                      _PayrollMetric(label: 'Paid', value: _money(grandPaid)),
                      _PayrollMetric(label: 'Outstanding', value: _money(grandEarned - grandPaid)),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: summaries.isEmpty
                  ? const Center(child: Text('No active staff members.'))
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: summaries),
            ),
          ],
        );
      },
    );
  }

  Future<void> _recordPayment(
    StaffMember staff,
    DateTime start,
    DateTime end,
    int duePaise,
  ) async {
    final controller = TextEditingController(text: (duePaise / 100).toStringAsFixed(2));
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Record payment – ${staff.name}'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount paid (₹)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value != null && value > 0) Navigator.pop(context, value);
            },
            child: const Text('Save payment'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (amount == null) return;
    final now = DateTime.now();
    await widget.repository.recordPayment(
      StaffPayment(
        staffId: staff.id!,
        staffUuid: staff.uuid,
        periodStart: start,
        periodEnd: end,
        paymentDate: now,
        amountPaise: (amount * 100).round(),
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (mounted) setState(() {});
  }

  String _statusLabel(String status) {
    switch (status) {
      case StaffAttendance.fullDay: return 'Full day';
      case StaffAttendance.halfDay: return 'Half day';
      case StaffAttendance.absent: return 'Absent';
      case StaffAttendance.leave: return 'Leave';
      default: return status;
    }
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  String _monthLabel(DateTime date) =>
      '${_monthNames[date.month - 1]} ${date.year}';

  String _money(int paise) => '₹${(paise / 100).toStringAsFixed(2)}';

  String _formatDuration(int minutes) {
    if (minutes == 0) return '0h';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
  }

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
}

class _PayrollMetric extends StatelessWidget {
  const _PayrollMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      );
}

class _StaffDialog extends StatefulWidget {
  const _StaffDialog({required this.repository, this.staff});

  final StaffRepository repository;
  final StaffMember? staff;

  @override
  State<_StaffDialog> createState() => _StaffDialogState();
}

class _StaffDialogState extends State<_StaffDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _role;
  late final TextEditingController _notes;
  late DateTime _joinedOn;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final staff = widget.staff;
    _name = TextEditingController(text: staff?.name ?? '');
    _phone = TextEditingController(text: staff?.phone ?? '');
    _role = TextEditingController(text: staff?.role ?? '');
    _notes = TextEditingController(text: staff?.notes ?? '');
    _joinedOn = staff?.joinedOn ?? DateTime.now();
    _active = staff?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _role.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final now = DateTime.now();
    final old = widget.staff;
    final member = StaffMember(
      id: old?.id,
      uuid: old?.uuid,
      name: _name.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      role: _role.text.trim().isEmpty ? null : _role.text.trim(),
      joinedOn: _joinedOn,
      isActive: _active,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
    );
    if (old == null) {
      await widget.repository.insertStaff(member);
    } else {
      await widget.repository.updateStaff(member);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.staff == null ? 'Add staff member' : 'Edit staff member'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (value) => value == null || value.trim().isEmpty ? 'Enter a name' : null,
                  ),
                  TextFormField(controller: _role, decoration: const InputDecoration(labelText: 'Role / designation')),
                  TextFormField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone')),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Date joined'),
                    subtitle: Text('${_joinedOn.day}/${_joinedOn.month}/${_joinedOn.year}'),
                    onTap: () async {
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: _joinedOn,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (selected != null) setState(() => _joinedOn = selected);
                    },
                  ),
                  TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes')),
                  if (widget.staff != null)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active staff member'),
                      value: _active,
                      onChanged: (value) => setState(() => _active = value),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      );
}

class _AttendanceDialog extends StatefulWidget {
  const _AttendanceDialog({
    required this.repository,
    required this.staff,
    required this.date,
    this.attendance,
  });

  final StaffRepository repository;
  final StaffMember staff;
  final DateTime date;
  final StaffAttendance? attendance;

  @override
  State<_AttendanceDialog> createState() => _AttendanceDialogState();
}

class _AttendanceDialogState extends State<_AttendanceDialog> {
  late String _status;
  TimeOfDay? _checkIn;
  TimeOfDay? _checkOut;
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    final record = widget.attendance;
    _status = record?.status ?? StaffAttendance.fullDay;
    _checkIn = _parseTime(record?.checkIn);
    _checkOut = _parseTime(record?.checkOut);
    _notes.text = record?.notes ?? '';
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  TimeOfDay? _parseTime(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String? _timeString(TimeOfDay? time) => time == null
      ? null
      : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  Future<TimeOfDay?> _pickTime(TimeOfDay? initial) => showTimePicker(
        context: context,
        initialTime: initial ?? const TimeOfDay(hour: 16, minute: 0),
      );

  Future<void> _save() async {
    if (_checkIn != null && _checkOut != null) {
      final inMinutes = _checkIn!.hour * 60 + _checkIn!.minute;
      final outMinutes = _checkOut!.hour * 60 + _checkOut!.minute;
      if (outMinutes <= inMinutes) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check-out must be later than check-in.')),
        );
        return;
      }
    }
    final now = DateTime.now();
    final old = widget.attendance;
    final record = StaffAttendance(
      id: old?.id,
      uuid: old?.uuid,
      staffId: widget.staff.id!,
      staffUuid: widget.staff.uuid,
      attendanceDate: widget.date,
      status: _status,
      checkIn: _timeString(_checkIn),
      checkOut: _timeString(_checkOut),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
    );
    await widget.repository.saveAttendance(record);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Attendance – ${widget.staff.name}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Attendance status'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  items: const [
                    DropdownMenuItem(value: StaffAttendance.fullDay, child: Text('Full day – ₹150')),
                    DropdownMenuItem(value: StaffAttendance.halfDay, child: Text('Half day – ₹75')),
                    DropdownMenuItem(value: StaffAttendance.absent, child: Text('Absent – ₹0')),
                    DropdownMenuItem(value: StaffAttendance.leave, child: Text('Leave – ₹0')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _status = value);
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Check-in (optional)'),
                  subtitle: Text(_checkIn?.format(context) ?? 'Not recorded'),
                  trailing: IconButton(
                    icon: const Icon(Icons.access_time),
                    onPressed: () async {
                      final time = await _pickTime(_checkIn ?? const TimeOfDay(hour: 10, minute: 0));
                      if (time != null) setState(() => _checkIn = time);
                    },
                  ),
                  onTap: () async {
                    final time = await _pickTime(_checkIn ?? const TimeOfDay(hour: 10, minute: 0));
                    if (time != null) setState(() => _checkIn = time);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Check-out (optional)'),
                  subtitle: Text(_checkOut?.format(context) ?? 'Not recorded'),
                  trailing: IconButton(
                    icon: const Icon(Icons.access_time),
                    onPressed: () async {
                      final time = await _pickTime(_checkOut);
                      if (time != null) setState(() => _checkOut = time);
                    },
                  ),
                  onTap: () async {
                    final time = await _pickTime(_checkOut);
                    if (time != null) setState(() => _checkOut = time);
                  },
                ),
                const Text('Overtime is calculated automatically for time worked before 10:00 AM and after 4:00 PM at ₹37.50/hour.'),
                const SizedBox(height: 12),
                TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _save, child: const Text('Save attendance')),
        ],
      );
}
