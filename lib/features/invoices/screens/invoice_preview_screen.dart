import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'package:printing/printing.dart';

import '../../customers/models/customer.dart';
import '../../orders/models/order.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';
import '../services/invoice_pdf_service.dart';

class InvoicePreviewScreen extends StatefulWidget {
  const InvoicePreviewScreen({
    super.key,
    required this.invoice,
    required this.invoiceItems,
    required this.order,
    required this.customer,
  });

  final Invoice invoice;
  final List<InvoiceItem> invoiceItems;
  final Order order;
  final Customer customer;

  @override
  State<InvoicePreviewScreen> createState() => _InvoicePreviewScreenState();
}

class _InvoicePreviewScreenState extends State<InvoicePreviewScreen> {
  bool _busy = false;

  Future<Uint8List> _pdf() => InvoicePdfService.generate(
        invoice: widget.invoice,
        invoiceItems: widget.invoiceItems,
        order: widget.order,
        customer: widget.customer,
      );

  Future<void> _preview() async {
    setState(() => _busy = true);
    try {
      final bytes = await _pdf();
      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: '${widget.invoice.invoiceNumber}.pdf',
      );
    } catch (error) {
      _error('Unable to generate invoice PDF: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final bytes = await _pdf();
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${widget.invoice.invoiceNumber}.pdf',
      );
    } catch (error) {
      _error('Unable to share invoice PDF: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _error(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  String _money(int paise) => '₹${(paise / 100).toStringAsFixed(2)}';

  String _date(DateTime value) {
    final d = value.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invoice')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.softGreige,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.receipt_long_rounded, color: AppColors.deepEspresso),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.invoice.invoiceNumber,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Order: ${widget.order.orderNumber}'),
                  Text('Customer: ${widget.customer.name}'),
                  Text('Invoice date: ${_date(widget.invoice.invoiceDate)}'),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _preview,
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('View / Print PDF'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _share,
                          icon: const Icon(Icons.share),
                          label: const Text('Share PDF'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  ...widget.invoiceItems.map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(child: Text(item.description)),
                          Text('${item.quantity} × ${_money(item.ratePaise)}'),
                          const SizedBox(width: 16),
                          Text(
                            _money(item.amountPaise),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 28, color: AppColors.warmGreige),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Amount Payable on Delivery',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        _money(widget.invoice.totalPaise),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
