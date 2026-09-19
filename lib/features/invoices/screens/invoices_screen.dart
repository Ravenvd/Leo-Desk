import 'package:flutter/material.dart';

import '../../customers/models/customer.dart';
import '../../customers/repositories/customer_repository.dart';
import '../../orders/repositories/order_repository.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';
import '../repositories/invoice_repository.dart';
import 'invoice_preview_screen.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({
    super.key,
    this.invoiceRepository,
    this.orderRepository,
    this.customerRepository,
  });

  final InvoiceRepository? invoiceRepository;
  final OrderRepository? orderRepository;
  final CustomerRepository? customerRepository;

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  late final InvoiceRepository _invoiceRepository;
  late final OrderRepository _orderRepository;
  late final CustomerRepository _customerRepository;

  List<Invoice> _invoices = [];
  Map<int, Customer> _customers = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _invoiceRepository = widget.invoiceRepository ?? InvoiceRepository();
    _orderRepository = widget.orderRepository ?? OrderRepository();
    _customerRepository = widget.customerRepository ?? CustomerRepository();
    _loadInvoices();
  }

  Future<void> _loadInvoices() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final invoices = await _invoiceRepository.getAll();
      final customers = <int, Customer>{};

      for (final invoice in invoices) {
        final customer = await _customerRepository.getById(invoice.customerId);
        if (customer != null) {
          customers[invoice.customerId] = customer;
        }
      }

      if (!mounted) return;
      setState(() {
        _invoices = invoices;
        _customers = customers;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Load invoices error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load invoices.';
      });
    }
  }

  Future<void> _openInvoice(Invoice invoice) async {
    try {
      final customer = _customers[invoice.customerId] ??
          await _customerRepository.getById(invoice.customerId);
      final order = await _orderRepository.getById(invoice.orderId);
      final items = invoice.id == null
          ? <InvoiceItem>[]
          : await _invoiceRepository.getItems(invoice.id!);

      if (customer == null || order == null || items.isEmpty) {
        _message('Unable to load the saved invoice.');
        return;
      }

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InvoicePreviewScreen(
            invoice: invoice,
            invoiceItems: items,
            order: order,
            customer: customer,
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Open invoice error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) _message('Unable to open the invoice.');
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _money(int paise) => '₹${(paise / 100).toStringAsFixed(2)}';

  String _date(DateTime value) {
    final d = value.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invoices')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadInvoices,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
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
            OutlinedButton.icon(
              onPressed: _loadInvoices,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    if (_invoices.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Text(
            'No invoices have been generated yet. An invoice is created automatically when an order enters In Progress.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: _invoices.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, index) => _buildInvoiceCard(_invoices[index]),
        ),
      ),
    );
  }

  Widget _buildInvoiceCard(Invoice invoice) {
    final customer = _customers[invoice.customerId];

    return Card(
      child: InkWell(
        onTap: () => _openInvoice(invoice),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const Icon(Icons.receipt_long_outlined, size: 36),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice.invoiceNumber,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(customer?.name ?? 'Customer unavailable'),
                    const SizedBox(height: 4),
                    Text(
                      'Invoice date: ${_date(invoice.invoiceDate)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                _money(invoice.totalPaise),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
