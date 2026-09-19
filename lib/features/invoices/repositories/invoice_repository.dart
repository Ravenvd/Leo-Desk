import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../customers/repositories/customer_repository.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';

class InvoiceRepository {
  final Database? database;

  InvoiceRepository({this.database});

  Future<Database> get _db async => database ?? await AppDatabase.database;

  Future<Invoice?> getByOrderUuid(String orderUuid) async {
    final db = await _db;
    final rows = await db.query(
      'invoices',
      where: 'order_uuid = ?',
      whereArgs: [orderUuid],
      limit: 1,
    );
    return rows.isEmpty ? null : Invoice.fromMap(rows.first);
  }

  Future<Invoice?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      'invoices',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Invoice.fromMap(rows.first);
  }

  Future<List<InvoiceItem>> getItems(int invoiceId) async {
    final db = await _db;
    final rows = await db.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'id ASC',
    );
    return rows.map(InvoiceItem.fromMap).toList();
  }

  Future<List<Invoice>> getAll() async {
    final db = await _db;
    final rows = await db.query(
      'invoices',
      orderBy: 'invoice_date DESC, id DESC',
    );
    return rows.map(Invoice.fromMap).toList();
  }

  Future<Invoice> create({
    required Invoice invoice,
    required List<InvoiceItem> items,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('An invoice must contain at least one item.');
    }

    final db = await _db;
    final existing = await getByOrderUuid(invoice.orderUuid);
    if (existing != null) return existing;

    var customerUuid = invoice.customerUuid;
    if (customerUuid == null) {
      final customer = await CustomerRepository(database: db).getById(
        invoice.customerId,
      );
      customerUuid = customer?.uuid;
    }

    final localInvoice = invoice.copyWith(
      syncStatus: 'pending',
      customerUuid: customerUuid,
    );

    final id = await db.transaction((txn) async {
      final invoiceId = await txn.insert(
        'invoices',
        localInvoice.toMap()..remove('id'),
      );

      for (final item in items) {
        await txn.insert(
          'invoice_items',
          item.toMap()
            ..remove('id')
            ..['invoice_id'] = invoiceId,
        );
      }

      return invoiceId;
    });

    return (await getById(id))!;
  }
}
