import 'package:flutter/material.dart';

import '../../customers/models/customer.dart';
import '../../customers/repositories/customer_repository.dart';
import '../models/bill.dart';
import '../repositories/bill_repository.dart';
import 'bill_details_screen.dart';

class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  final BillRepository _billRepository = BillRepository();
  final CustomerRepository _customerRepository = CustomerRepository();

  List<Bill> _bills = [];
  final Map<int, Customer> _customers = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  Future<void> _loadBills() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final bills = await _billRepository.getAll();
      for (final bill in bills) {
        final customerId = bill.customerId;
        if (!_customers.containsKey(customerId)) {
          final customer = await _customerRepository.getById(customerId);
          if (customer != null) _customers[customerId] = customer;
        }
      }

      if (!mounted) return;
      setState(() {
        _bills = bills;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Load bills error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load bills.';
      });
    }
  }

  String _date(DateTime value) {
    final d = value.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _money(int paise) => '₹${(paise / 100).toStringAsFixed(2)}';

  Future<void> _openBill(Bill bill) async {
    final customer = _customers[bill.customerId];
    if (customer == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BillDetailsScreen(
          bill: bill,
          repository: _billRepository,
          customer: customer,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bills',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '${_bills.length} bill${_bills.length == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 16),
            Text(_error!),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _loadBills, child: const Text('Try Again')),
          ],
        ),
      );
    }
    if (_bills.isEmpty) {
      return const Center(
        child: Text('No bills yet. Bills are generated automatically when an order is completed.'),
      );
    }

    return Card(
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Bill')),
              DataColumn(label: Text('Customer')),
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Amount')),
              DataColumn(label: Text('Status')),
            ],
            rows: _bills.map((bill) {
              final customer = _customers[bill.customerId];
              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      bill.billNumber,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () => _openBill(bill),
                  ),
                  DataCell(Text(customer?.name ?? 'Unknown customer')),
                  DataCell(Text(_date(bill.billDate))),
                  DataCell(
                    Text(
                      _money(bill.totalPaise),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const DataCell(
                    Chip(
                      label: Text('Paid'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}