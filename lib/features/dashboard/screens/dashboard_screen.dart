import 'package:flutter/material.dart';

import '../../billing/models/bill.dart';
import '../../billing/repositories/bill_repository.dart';
import '../../billing/screens/bill_details_screen.dart';
import '../../customers/models/customer.dart';
import '../../customers/repositories/customer_repository.dart';

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
  List<Customer> _customers = [];
  List<Bill> _bills = [];
  int _pendingSyncCount = 0;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
          _buildRecentBills(),
        ],
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
