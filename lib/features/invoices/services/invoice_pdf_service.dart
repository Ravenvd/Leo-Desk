import 'package:flutter/services.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../customers/models/customer.dart';
import '../../orders/models/order.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';

class InvoicePdfService {
  static const businessName = 'Leo Stitch & Design';
  static const businessLocation = 'Kodunkulam, Marthandam';

  static final _espresso = PdfColor.fromInt(0xFF5F584E);
  static final _darkEspresso = PdfColor.fromInt(0xFF403B35);
  static final _ivory = PdfColor.fromInt(0xFFFAF7F0);
  static final _greige = PdfColor.fromInt(0xFFD8D0C4);
  static final _taupe = PdfColor.fromInt(0xFF9A8F80);

  static Future<Uint8List> generate({
    required Invoice invoice,
    required List<InvoiceItem> invoiceItems,
    required Order order,
    required Customer customer,
  }) async {
    final logoBytes = (await rootBundle.load('assets/images/leo_logo.png')).buffer.asUint8List();
    final logo = pw.MemoryImage(logoBytes);
    final document = pw.Document();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => [
          pw.Container(
            padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 14),
            decoration: pw.BoxDecoration(
              color: _ivory,
              border: pw.Border(bottom: pw.BorderSide(color: _greige, width: 1)),
            ),
            child: pw.Row(
              children: [
                pw.Image(logo, width: 82, height: 64, fit: pw.BoxFit.contain),
                pw.SizedBox(width: 12),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      businessName,
                      style: pw.TextStyle(
                        color: _darkEspresso,
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'Machine Embroidery & Aari',
                      style: pw.TextStyle(color: _taupe, fontSize: 8.5),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      businessLocation,
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Container(height: 4, color: _espresso),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'INVOICE',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Invoice No: ${invoice.invoiceNumber}', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('Invoice Date: ${_date(invoice.invoiceDate)}', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('Order No: ${order.orderNumber}', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('Order Date: ${_date(order.orderDate)}', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: .7),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Customer',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  customer.name,
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                if (customer.phone?.trim().isNotEmpty == true)
                  pw.Text('Phone: ${customer.phone}', style: const pw.TextStyle(fontSize: 8)),
                if (customer.whatsapp?.trim().isNotEmpty == true)
                  pw.Text('WhatsApp: ${customer.whatsapp}', style: const pw.TextStyle(fontSize: 8)),
                if (customer.email?.trim().isNotEmpty == true)
                  pw.Text('Email: ${customer.email}', style: const pw.TextStyle(fontSize: 8)),
                if (customer.address?.trim().isNotEmpty == true)
                  pw.Text('Address: ${customer.address}', style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
          ),
          pw.SizedBox(height: 24),
          pw.TableHelper.fromTextArray(
            headers: const ['Description', 'Qty', 'Rate', 'Amount'],
            data: invoiceItems
                .map(
                  (item) => [
                    item.description,
                    item.quantity.toString(),
                    _money(item.ratePaise),
                    _money(item.amountPaise),
                  ],
                )
                .toList(),
            border: pw.TableBorder.all(color: _greige, width: .5),
            headerDecoration: pw.BoxDecoration(color: _espresso),
            cellPadding: const pw.EdgeInsets.all(7),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
            ),
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
                  _row('Subtotal', invoice.subtotalPaise),
                  pw.Divider(),
                  _row(
                    'Amount Payable on Delivery',
                    invoice.totalPaise,
                    bold: true,
                  ),
                ],
              ),
            ),
          ),
          if (invoice.notes?.trim().isNotEmpty == true) ...[
            pw.SizedBox(height: 24),
            pw.Text(
              'Order Notes',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Text(
              invoice.notes!,
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
          pw.SizedBox(height: 30),
          pw.Center(
            child: pw.Text(
              'Thank you for your business.',
              style: pw.TextStyle(
                fontStyle: pw.FontStyle.italic,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );

    return document.save();
  }

  static pw.Widget _row(String label, int paise, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight:
                  bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            _money(paise),
            style: pw.TextStyle(
              fontWeight:
                  bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  static String _money(int paise) =>
      'Rs. ${(paise / 100).toStringAsFixed(2)}';

  static String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
