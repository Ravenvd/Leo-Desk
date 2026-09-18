import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../customers/models/customer.dart';
import '../../../orders/models/order.dart';
import '../../../orders/models/order_item.dart';

class InvoicePdfService {
  static const businessName = 'Leo Stitch and Design';
  static const businessLocation = 'Kodunkulam, Marthandam';

  static Future<Uint8List> generate({
    required Order order,
    required List<OrderItem> items,
    required Customer customer,
    required DateTime invoiceDate,
  }) async {
    final document = pw.Document();
    final itemsTotal = items.fold<int>(
      0,
      (total, item) => total + item.quantity * item.unitPricePaise,
    );
    final total = itemsTotal + order.stitchingPricePaise;

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                businessName,
                style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text(businessLocation, style: const pw.TextStyle(fontSize: 11)),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Divider(),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'INVOICE',
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Invoice No: INV-${_orderNumber(order.orderNumber)}'),
                  pw.Text('Invoice Date: ${_date(invoiceDate)}'),
                  pw.Text('Order No: ${order.orderNumber}'),
                  pw.Text('Order Date: ${_date(order.orderDate)}'),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: .7)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Customer', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                pw.SizedBox(height: 5),
                pw.Text(customer.name, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                if (customer.phone?.trim().isNotEmpty == true) pw.Text('Phone: ${customer.phone}'),
                if (customer.whatsapp?.trim().isNotEmpty == true) pw.Text('WhatsApp: ${customer.whatsapp}'),
                if (customer.email?.trim().isNotEmpty == true) pw.Text('Email: ${customer.email}'),
                if (customer.address?.trim().isNotEmpty == true) pw.Text('Address: ${customer.address}'),
              ],
            ),
          ),
          pw.SizedBox(height: 24),
          pw.TableHelper.fromTextArray(
            headers: const ['Description', 'Qty', 'Rate', 'Amount'],
            data: items.map((item) => [
              '${item.workType} - ${item.garmentType}${item.notes?.trim().isNotEmpty == true ? ' | ${item.notes}' : ''}',
              item.quantity.toString(),
              _money(item.unitPricePaise),
              _money(item.quantity * item.unitPricePaise),
            ]).toList(),
            border: pw.TableBorder.all(width: .5),
            cellPadding: const pw.EdgeInsets.all(7),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: {
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 18),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 250,
              child: pw.Column(
                children: [
                  _row('Items Total', itemsTotal),
                  if (order.stitchingRequired) _row('Stitching', order.stitchingPricePaise),
                  pw.Divider(),
                  _row('Total', total, bold: true),
                ],
              ),
            ),
          ),
          if (order.notes?.trim().isNotEmpty == true) ...[
            pw.SizedBox(height: 24),
            pw.Text('Order Notes', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.SizedBox(height: 5),
            pw.Text(order.notes!, style: const pw.TextStyle(fontSize: 9)),
          ],
          pw.SizedBox(height: 30),
          pw.Center(
            child: pw.Text('Thank you for your business.', style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 10)),
          ),
        ],
      ),
    );

    return document.save();
  }

  static String _orderNumber(String orderNumber) =>
      orderNumber.startsWith('ORD-') ? orderNumber.substring(4) : orderNumber;

  static pw.Widget _row(String label, int paise, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(_money(paise), style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );
  }

  static String _money(int paise) => 'Rs. ${(paise / 100).toStringAsFixed(2)}';

  static String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
