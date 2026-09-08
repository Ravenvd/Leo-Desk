import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../customers/models/customer.dart';
import '../models/bill.dart';
import '../models/bill_item.dart';
import '../repositories/bill_repository.dart';
import '../services/bill_pdf_service.dart';

class BillDetailsScreen extends StatefulWidget {
  const BillDetailsScreen({
    super.key,
    required this.bill,
    required this.repository,
    required this.customer,
  });

  final Bill bill;
  final BillRepository repository;
  final Customer customer;

  @override
  State<BillDetailsScreen> createState() => _BillDetailsScreenState();
}

class _BillDetailsScreenState extends State<BillDetailsScreen> {
  late Future<List<BillItem>> _items;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _items = widget.repository.getItems(widget.bill.id!);
  }

  String _money(int paise) => 'Rs. ${(paise / 100).toStringAsFixed(2)}';

  String _date(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  Future<Uint8List> _pdf(List<BillItem> items) {
    return BillPdfService.generate(
      bill: widget.bill,
      items: items,
      customer: widget.customer,
    );
  }

  Future<void> _preview(List<BillItem> items) async {
    if (widget.bill.amountPaidPaise != widget.bill.totalPaise) {
      _error('A bill can only be generated after full payment.');
      return;
    }

    setState(() => _busy = true);

    try {
      final bytes = await _pdf(items);
      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: '${widget.bill.billNumber}.pdf',
      );
    } catch (error) {
      _error('Unable to generate PDF: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(List<BillItem> items) async {
    if (widget.bill.amountPaidPaise != widget.bill.totalPaise) {
      _error('A bill can only be generated after full payment.');
      return;
    }

    setState(() => _busy = true);

    try {
      final bytes = await _pdf(items);
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${widget.bill.billNumber}.pdf',
      );
    } catch (error) {
      _error('Unable to share PDF: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _error(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bill Details')),
      body: FutureBuilder<List<BillItem>>(
        future: _items,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Unable to load bill items.\n${snapshot.error}',
              ),
            );
          }

          final items = snapshot.data ?? <BillItem>[];

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildHeaderCard(context),
              const SizedBox(height: 18),
              _buildCustomerCard(context),
              const SizedBox(height: 18),
              _buildItemsCard(items),
              const SizedBox(height: 18),
              _buildTotalsCard(),
              if (widget.bill.notes?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 18),
                _buildNotesCard(),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.bill.billNumber,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const Chip(label: Text('Paid')),
              ],
            ),
            const SizedBox(height: 12),
            Text('Bill date: ${_date(widget.bill.billDate)}'),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : () => _previewFromCard(),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('View / Print PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _shareFromCard(),
                  icon: const Icon(Icons.share),
                  label: const Text('Share PDF'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _previewFromCard() async {
    final items = await _items;
    if (mounted) await _preview(items);
  }

  Future<void> _shareFromCard() async {
    final items = await _items;
    if (mounted) await _share(items);
  }

  Widget _buildCustomerCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Customer',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              widget.customer.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (widget.customer.phone?.trim().isNotEmpty == true)
              Text(widget.customer.phone!),
            if (widget.customer.whatsapp?.trim().isNotEmpty == true)
              Text('WhatsApp: ${widget.customer.whatsapp!}'),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsCard(List<BillItem> items) {
    return Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Items',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...items.map(
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
              ],
            ),
          ),
        );
  }

  Widget _buildTotalsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _row('Subtotal', widget.bill.subtotalPaise),
            if (widget.bill.discountPaise != 0)
              _row('Discount', widget.bill.discountPaise),
            if (widget.bill.taxPaise != 0)
              _row('Tax', widget.bill.taxPaise),
            const Divider(),
            _row('Total', widget.bill.totalPaise, bold: true),
            _row(
              'Amount Received',
              widget.bill.amountPaidPaise,
              bold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notes',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(widget.bill.notes!),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, int paise, {bool bold = false}) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.w700) : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(_money(paise), style: style),
        ],
      ),
    );
  }
}
