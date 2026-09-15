import 'package:flutter/material.dart';

import '../../billing/models/bill.dart';
import '../../billing/repositories/bill_repository.dart';
import '../../billing/screens/bill_details_screen.dart';
import '../../customers/models/customer.dart';
import '../../customers/repositories/customer_repository.dart';
import '../../../core/sync/sync_events.dart';
import '../widgets/dashboard_charts.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.customerRepository,
    required this.billRepository,
  });

  final CustomerRepository customerRepository;
  final BillRepository billRepository;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  /// Initial business investment: ₹10,00,000 (in paise).
  static const int _investmentPaise = 100000000;

  List<Customer> _customers = [];
  List<Bill> _bills = [];
  int _pendingSyncCount = 0;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    syncCompleted.addListener(_onSyncCompleted);
  }

  void _onSyncCompleted() {
    if (mounted) {
      _load();
    }
  }

  @override
  void dispose() {
    syncCompleted.removeListener(_onSyncCompleted);
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final customers = await widget.customerRepository.getAll();
      final bills = await widget.billRepository.getAll();
      final pendingCustomers = await widget.customerRepository.getPending();
      final pendingBills = await widget.billRepository.getPending();

      if (!mounted) return;

      setState(() {
        _customers = customers;
        _bills = bills;
        _pendingSyncCount = pendingCustomers.length + pendingBills.length;
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Load dashboard error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _error = 'Unable to load the dashboard.';
        _isLoading = false;
      });
    }
  }

  String _money(int paise) => '₹${(paise / 100).toStringAsFixed(2)}';

  String _date(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 28),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dashboard',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          'Your business at a glance.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 16),
            Text(_error!),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _load, child: const Text('Try Again')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          _buildStats(),
          const SizedBox(height: 28),
          _buildBreakevenCard(),
          const SizedBox(height: 16),
          _buildEarningsChart(),
          const SizedBox(height: 16),
          _buildCustomersChart(),
          const SizedBox(height: 16),
          NetworthChart(points: _networthPoints()),
          const SizedBox(height: 28),
          _buildRecentBills(),
        ],
      ),
    );
  }

  int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  List<double> _cumulative(List<double> daily) {
    var sum = 0.0;
    return [for (final value in daily) sum += value];
  }

  /// Cumulative earnings (in rupees) per day of the given month,
  /// up to and including [maxDay].
  List<double> _cumulativeEarnings(int year, int month, int maxDay) {
    final daily = List<double>.filled(maxDay, 0);

    for (final bill in _bills) {
      final date = bill.billDate;
      if (date.year == year && date.month == month && date.day <= maxDay) {
        daily[date.day - 1] += bill.totalPaise / 100;
      }
    }

    return _cumulative(daily);
  }

  /// Cumulative new-customer count per day of the given month.
  List<double> _cumulativeCustomers(int year, int month, int maxDay) {
    final daily = List<double>.filled(maxDay, 0);

    for (final customer in _customers) {
      final date = customer.createdAt;
      if (date.year == year && date.month == month && date.day <= maxDay) {
        daily[date.day - 1] += 1;
      }
    }

    return _cumulative(daily);
  }

  Widget _buildEarningsChart() {
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1);
    final lastMonthMaxDay =
        now.day > _daysInMonth(lastMonth.year, lastMonth.month)
        ? _daysInMonth(lastMonth.year, lastMonth.month)
        : now.day;

    return MonthComparisonChart(
      title: 'Earnings — this month vs last month',
      lastMonth: _cumulativeEarnings(
        lastMonth.year,
        lastMonth.month,
        lastMonthMaxDay,
      ),
      thisMonth: _cumulativeEarnings(now.year, now.month, now.day),
    );
  }

  Widget _buildCustomersChart() {
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1);
    final lastMonthMaxDay =
        now.day > _daysInMonth(lastMonth.year, lastMonth.month)
        ? _daysInMonth(lastMonth.year, lastMonth.month)
        : now.day;

    return MonthComparisonChart(
      title: 'New customers — this month vs last month',
      lastMonth: _cumulativeCustomers(
        lastMonth.year,
        lastMonth.month,
        lastMonthMaxDay,
      ),
      thisMonth: _cumulativeCustomers(now.year, now.month, now.day),
      formatValue: (value) => value.toInt().toString(),
    );
  }

  /// Net worth per day: cumulative revenue minus the initial investment,
  /// from the first bill's date until today.
  List<NetworthPoint> _networthPoints() {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    if (_bills.isEmpty) {
      return [
        NetworthPoint(date: todayDate, networthRupees: -_investmentPaise / 100),
      ];
    }

    final revenueByDay = <DateTime, int>{};
    for (final bill in _bills) {
      final day = DateTime(
        bill.billDate.year,
        bill.billDate.month,
        bill.billDate.day,
      );
      revenueByDay[day] = (revenueByDay[day] ?? 0) + bill.totalPaise;
    }

    final firstDay = revenueByDay.keys.reduce((a, b) => a.isBefore(b) ? a : b);

    final points = <NetworthPoint>[];
    var cumulativePaise = 0;

    for (
      var day = firstDay;
      !day.isAfter(todayDate);
      day = day.add(const Duration(days: 1))
    ) {
      cumulativePaise += revenueByDay[day] ?? 0;
      points.add(
        NetworthPoint(
          date: day,
          networthRupees: (cumulativePaise - _investmentPaise) / 100,
        ),
      );
    }

    return points;
  }

  Widget _buildBreakevenCard() {
    final totalRevenue = _bills.fold<int>(
      0,
      (sum, bill) => sum + bill.totalPaise,
    );
    final remaining = _investmentPaise - totalRevenue;

    final colorScheme = Theme.of(context).colorScheme;

    String title;
    String subtitle;
    Color accent;

    if (remaining <= 0) {
      title = 'Breakeven achieved 🎉';
      subtitle =
          'Earnings of ${_money(totalRevenue)} have covered the '
          '${_money(_investmentPaise)} investment.';
      accent = Colors.green;
    } else if (totalRevenue <= 0) {
      title = 'Breakeven countdown';
      subtitle =
          'No earnings yet — add bills to start the projection. '
          '${_money(remaining)} to go.';
      accent = colorScheme.primary;
    } else {
      final firstBillDate = _bills
          .map((bill) => bill.billDate)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final daysTracked = DateTime.now().difference(firstBillDate).inDays + 1;
      final averageDailyPaise = totalRevenue / daysTracked;
      final estimatedDays = (remaining / averageDailyPaise).ceil();
      final projectedDate = DateTime.now().add(Duration(days: estimatedDays));

      title = '≈ $estimatedDays days to breakeven';
      subtitle =
          'At the current average of ${_money(averageDailyPaise.round())}'
          '/day, projected around ${_date(projectedDate)}. '
          '${_money(remaining)} to go.';
      accent = colorScheme.primary;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Icon(Icons.flag_rounded, size: 40, color: accent),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(color: accent),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats() {
    final totalRevenue = _bills.fold<int>(
      0,
      (sum, bill) => sum + bill.totalPaise,
    );
    final outstanding = _bills.fold<int>(
      0,
      (sum, bill) =>
          sum + (bill.balanceDuePaise > 0 ? bill.balanceDuePaise : 0),
    );

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _StatCard(
          icon: Icons.people_alt_rounded,
          label: 'Customers',
          value: '${_customers.length}',
        ),
        _StatCard(
          icon: Icons.receipt_long_rounded,
          label: 'Bills',
          value: '${_bills.length}',
        ),
        _StatCard(
          icon: Icons.payments_rounded,
          label: 'Revenue',
          value: _money(totalRevenue),
        ),
        _StatCard(
          icon: Icons.account_balance_wallet_rounded,
          label: 'Outstanding',
          value: _money(outstanding),
          highlight: outstanding > 0,
        ),
        _StatCard(
          icon: Icons.sync_rounded,
          label: 'Pending sync',
          value: '$_pendingSyncCount',
          highlight: _pendingSyncCount > 0,
        ),
      ],
    );
  }

  Widget _buildRecentBills() {
    final customerNames = {
      for (final customer in _customers)
        if (customer.id != null) customer.id!: customer,
    };

    final recentBills = _bills.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recent bills', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (recentBills.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No bills yet.'),
            ),
          )
        else
          for (final bill in recentBills)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RecentBillCard(
                bill: bill,
                customer: customerNames[bill.customerId],
                money: _money,
                date: _date,
                onTap: () => _openBill(bill, customerNames[bill.customerId]),
              ),
            ),
      ],
    );
  }

  Future<void> _openBill(Bill bill, Customer? customer) async {
    if (customer == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BillDetailsScreen(
          bill: bill,
          repository: widget.billRepository,
          customer: customer,
        ),
      ),
    );

    if (!mounted) return;
    await _load();
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Draws attention to the value (e.g. outstanding dues, pending sync).
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 200,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: highlight ? colorScheme.error : colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: highlight ? colorScheme.error : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentBillCard extends StatelessWidget {
  const _RecentBillCard({
    required this.bill,
    required this.customer,
    required this.money,
    required this.date,
    required this.onTap,
  });

  final Bill bill;
  final Customer? customer;
  final String Function(int paise) money;
  final String Function(DateTime date) date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusLabel = switch (bill.paymentStatus) {
      'paid' => 'Paid',
      'partial' => 'Partial',
      _ => 'Unpaid',
    };

    final statusColor = switch (bill.paymentStatus) {
      'paid' => Colors.green,
      'partial' => Colors.orange,
      _ => Colors.red,
    };

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        title: Text(
          bill.billNumber,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${customer?.name ?? 'Unknown customer'} · ${date(bill.billDate)}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              money(bill.totalPaise),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(width: 12),
            Chip(
              label: Text(statusLabel),
              labelStyle: TextStyle(color: statusColor),
              side: BorderSide(color: statusColor),
              backgroundColor: statusColor.withValues(alpha: 0.08),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        onTap: customer == null ? null : onTap,
      ),
    );
  }
}
