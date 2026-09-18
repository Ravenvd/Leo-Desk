import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../customers/models/customer.dart';
import '../../orders/models/order.dart';
import '../../orders/models/order_item.dart';
import '../services/invoice_pdf_service.dart';

class InvoicePreviewScreen extends StatefulWidget {
  const InvoicePreviewScreen({
    super.key,
    required this.order,
    required this.items,
    required this.customer,
  });

  final Order order;
  final List<OrderItem> items;
  final Customer customer;

  @override
  State<InvoicePreviewScreen> createState() => _InvoicePreviewScreenState();
}

class _InvoicePreviewScreenState extends State<InvoicePreviewScreen> {
  late final DateTime _invoiceDate;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _invoiceDate = DateTime.now();
  }

  Future<Uint8List> _pdf() => InvoicePdfService.generate(
        order: widget.order,
        items: widget.items,
        customer: widget.customer,
        invoiceDate: _invoiceDate,
      );

  Future<void> _preview() async {
    setState(() => _busy = true);
    try {
      final bytes = await _pdf();
      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: 'INV-${_number(widget.order.orderNumber)}.pdf',
      );
    } catch (error) {
      _error('Unable to generate invoice PDF: ${error}');
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
        filename: 'INV-${_number(widget.order.orderNumber)}.pdf',
      );
    } catch (error) {
      _error('Unable to share invoice PDF: ${error}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _error(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  int get _itemsTotal => widget.items.fold(
        0,
        (total, item) => total + item.quantity * item.unitPricePaise,
      );

  int get _total => _itemsTotal + widget.order.stitchingPricePaise;

  String _number(String value) => value.startsWith('ORD-') ? value.substring(4) : value;

  String _money(int paise) => 'Rs. ${(paise / 100).toStringAsFixed(2)}';

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
                      const Icon(Icons.receipt_long_rounded, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'INV-${_number(widget.order.orderNumber)}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Order: ${widget.order.orderNumber}'),
                  Text('Customer: ${widget.customer.name}'),
                  Text('Invoice date: ${_date(_invoiceDate)}'),
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
                  ...widget.items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(child: Text('${item.workType} · ${item.garmentType}')),
                          Text('${item.quantity} × ${_money(item.unitPricePaise)}'),
                          const SizedBox(width: 16),
                          Text(
                            _money(item.quantity * item.unitPricePaise),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.order.stitchingRequired)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const Expanded(child: Text('Stitching')),
                          Text(_money(widget.order.stitchingPricePaise)),
                        ],
                      ),
                    ),
                  const Divider(height: 28),
                  Row(
                    children: [
                      const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w700))),
                      Text(_money(_total), style: const TextStyle(fontWeight: FontWeight.w700)),
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
