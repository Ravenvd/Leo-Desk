import 'package:flutter/material.dart';

import '../../billing/models/bill.dart';
import '../../billing/repositories/bill_repository.dart';
import '../../billing/screens/bill_details_screen.dart';
import '../../customers/models/customer.dart';
import '../../customers/repositories/customer_repository.dart';
import '../../expenses/models/expense.dart';
import '../../expenses/repositories/expense_repository.dart';
import '../../orders/models/order.dart';
import '../../invoices/models/invoice.dart';
import '../../invoices/repositories/invoice_repository.dart';
import '../../orders/repositories/order_repository.dart';
import '../../../core/sync/sync_events.dart';
import '../widgets/dashboard_charts.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.customerRepository,
    required this.billRepository,
    required this.expenseRepository,
    required this.invoiceRepository,
  });

  final CustomerRepository customerRepository;
  final BillRepository billRepository;
  final ExpenseRepository expenseRepository;
  final InvoiceRepository invoiceRepository;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  /// Initial business investment: ₹10,00,000 (in paise).
  static const int _investmentPaise = 100000000;

  List<Customer> _customers = [];
  List<Bill> _bills = [];
  List<Invoice> _invoices = [];
  List<Expense> _expenses = [];
  List<Order> _orders = [];
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
      final invoices = await widget.invoiceRepository.getAll();
      final expenses = await widget.expenseRepository.getAll();
      final orders = await OrderRepository().getAll();
      final pendingCustomers = await widget.customerRepository.getPending();
      final pendingBills = await widget.billRepository.getPending();
      final pendingExpenses = await widget.expenseRepository.getPending();

      if (!mounted) return;

      setState(() {
        _customers = customers;
        _bills = bills;
        _invoices = invoices;
        _expenses = expenses;
        _orders = orders;
        _pendingSyncCount =
            pendingCustomers.length + pendingBills.length + pendingExpenses.length;
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

  int get _totalRevenuePaise =>
      _bills.fold<int>(0, (sum, bill) => sum + bill.totalPaise);

  int get _totalExpensesPaise =>
      _expenses.fold<int>(0, (sum, expense) => sum + expense.amountPaise);

  int get _netProfitPaise => _totalRevenuePaise - _totalExpensesPaise;

  int get _amountPendingPaise {
    final invoicedPaise =
        _invoices.fold<int>(0, (sum, invoice) => sum + invoice.totalPaise);
    final paidPaise =
        _bills.fold<int>(0, (sum, bill) => sum + bill.amountPaidPaise);
    return (invoicedPaise - paidPaise).clamp(0, invoicedPaise);
  }


  int get _pendingOrdersCount => _orders.where((order) {
    return order.status == 'New' || order.status == 'In Progress';
  }).length;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
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
          _buildBreakevenCard(),
          const SizedBox(height: 20),
          _buildStats(),
          const SizedBox(height: 28),
          _buildEarningsChart(),
          const SizedBox(height: 16),
          _buildCustomersChart(),
          const SizedBox(height: 16),
          NetworthChart(points: _networthPoints()),
          const SizedBox(height: 28),
          _buildRecentTransactions(),
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

  /// Net worth at the end of each calendar month: initial investment plus
  /// cumulative revenue minus cumulative expenses. The current month is
  /// calculated up to today.
  List<NetworthPoint> _networthPoints() {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    final transactionDates = [
      ..._bills.map((bill) => DateTime(
            bill.billDate.year,
            bill.billDate.month,
            bill.billDate.day,
          )),
      ..._expenses.map((expense) => DateTime(
            expense.expenseDate.year,
            expense.expenseDate.month,
            expense.expenseDate.day,
          )),
    ];

    if (transactionDates.isEmpty) {
      return [
        NetworthPoint(
          date: DateTime(today.year, today.month, 1),
          networthRupees: _investmentPaise / 100,
        ),
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

    final expensesByDay = <DateTime, int>{};
    for (final expense in _expenses) {
      final day = DateTime(
        expense.expenseDate.year,
        expense.expenseDate.month,
        expense.expenseDate.day,
      );
      expensesByDay[day] =
          (expensesByDay[day] ?? 0) + expense.amountPaise;
    }

    final firstTransactionDay =
        transactionDates.reduce((a, b) => a.isBefore(b) ? a : b);
    final firstMonth =
        DateTime(firstTransactionDay.year, firstTransactionDay.month, 1);
    final points = <NetworthPoint>[];
    var cumulativePaise = _investmentPaise;

    for (
      var month = firstMonth;
      !month.isAfter(todayDate);
      month = DateTime(month.year, month.month + 1, 1)
    ) {
      final monthEnd = DateTime(month.year, month.month + 1, 0);
      final endDate = monthEnd.isAfter(todayDate) ? todayDate : monthEnd;

      for (
        var day = month;
        !day.isAfter(endDate);
        day = day.add(const Duration(days: 1))
      ) {
        cumulativePaise += revenueByDay[day] ?? 0;
      }

      points.add(
        NetworthPoint(
          date: endDate,
          networthRupees: cumulativePaise / 100,
        ),
      );
    }

    return points;
  }

  Widget _buildBreakevenCard() {
    final totalRevenue = _totalRevenuePaise;
    final remaining = _investmentPaise - _netProfitPaise;
    final achieved = remaining <= 0;
    final colorScheme = Theme.of(context).colorScheme;
    final accent = achieved ? Colors.green : colorScheme.primary;

    String subtitle;
    if (achieved) {
      subtitle =
          'Your recorded net profit has covered the '
          '${_money(_investmentPaise)} initial investment.';
    } else if (totalRevenue <= 0) {
      subtitle = 'Start recording bills to track progress towards breakeven.';
    } else {
      final firstBillDate = _bills
          .map((bill) => bill.billDate)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final daysTracked = DateTime.now().difference(firstBillDate).inDays + 1;
      final netProfitPaise = totalRevenue - _totalExpensesPaise;
      final averageDailyPaise = netProfitPaise / daysTracked;
      final estimatedDays = netProfitPaise > 0
          ? (remaining / averageDailyPaise).ceil()
          : 0;
      final projectedDate = DateTime.now().add(Duration(days: estimatedDays));
      subtitle =
          'At the current average net profit of ${_money(averageDailyPaise.round())}/day, '
          'projected around ${_date(projectedDate)}.';
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
                    achieved ? 'Breakeven achieved 🎉' : 'Amount to breakeven',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    achieved ? '₹0.00 remaining' : '${_money(remaining)} remaining',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
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
          icon: Icons.payments_rounded,
          label: 'Revenue',
          value: _money(_totalRevenuePaise),
        ),
        _StatCard(
          icon: Icons.account_balance_wallet_rounded,
          label: 'Amount pending',
          value: _money(_amountPendingPaise),
          highlight: _amountPendingPaise > 0,
        ),
        _StatCard(
          icon: Icons.trending_up_rounded,
          label: 'Net profit',
          value: _money(_netProfitPaise),
          highlight: _netProfitPaise < 0,
        ),
        _StatCard(
          icon: Icons.pending_actions_rounded,
          label: 'Pending orders',
          value: '$_pendingOrdersCount',
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

  Widget _buildRecentTransactions() {
    final customerNames = {
      for (final customer in _customers)
        if (customer.id != null) customer.id!: customer,
    };

    final transactions = <_RecentTransaction>[
      for (final bill in _bills) _RecentTransaction.bill(bill),
      for (final expense in _expenses) _RecentTransaction.expense(expense),
    ]..sort((a, b) => b.date.compareTo(a.date));

    final recentTransactions = transactions.take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent transactions',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Card(
          child: recentTransactions.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No transactions yet.'),
                )
              : Column(
                  children: [
                    for (var i = 0; i < recentTransactions.length; i++) ...[
                      _buildTransactionTile(
                        recentTransactions[i],
                        customerNames,
                      ),
                      if (i < recentTransactions.length - 1)
                        const Divider(height: 1),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildTransactionTile(
    _RecentTransaction transaction,
    Map<int, Customer> customerNames,
  ) {
    if (transaction.bill != null) {
      final bill = transaction.bill!;
      final customer = customerNames[bill.customerId];
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

      return ListTile(
        leading: const Icon(Icons.receipt_long_rounded),
        title: Text(
          bill.billNumber,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${customer?.name ?? 'Unknown customer'} · ${_date(bill.billDate)}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _money(bill.totalPaise),
              style: const TextStyle(fontWeight: FontWeight.w600),
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
        onTap: customer == null ? null : () => _openBill(bill, customer),
      );
    }

    final expense = transaction.expense!;
    return ListTile(
      leading: const Icon(Icons.money_off_rounded),
      title: Text(
        expense.description,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text('${expense.category} · ${_date(expense.expenseDate)}'),
      trailing: Text(
        '-${_money(expense.amountPaise)}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<void> _openBill(Bill bill, Customer customer) async {
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

class _RecentTransaction {
  final DateTime date;
  final Bill? bill;
  final Expense? expense;

  const _RecentTransaction._({
    required this.date,
    this.bill,
    this.expense,
  });

  factory _RecentTransaction.bill(Bill bill) {
    return _RecentTransaction._(date: bill.billDate, bill: bill);
  }

  factory _RecentTransaction.expense(Expense expense) {
    return _RecentTransaction._(
      date: expense.expenseDate,
      expense: expense,
    );
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
