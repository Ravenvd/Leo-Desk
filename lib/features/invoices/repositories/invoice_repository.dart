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

  Future<List<Invoice>> getPending() async {
    final db = await _db;
    final rows = await db.query(
      'invoices',
      where: 'sync_status = ?',
      whereArgs: ['pending'],
      orderBy: 'invoice_date ASC, id ASC',
    );
    return rows.map(Invoice.fromMap).toList();
  }

  Future<int> markSynced(String uuid) async {
    final db = await _db;
    return db.update(
      'invoices',
      {'sync_status': 'synced'},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<bool> upsertFromSync(
    Invoice invoice,
    List<InvoiceItem> items, {
    bool force = false,
  }) async {
    final db = await _db;

    final existing = await db.query(
      'invoices',
      columns: ['id', 'sync_status'],
      where: 'uuid = ?',
      whereArgs: [invoice.uuid],
      limit: 1,
    );

    if (!force &&
        existing.isNotEmpty &&
        existing.first['sync_status'] == 'pending') {
      return false;
    }

    if (invoice.customerUuid == null) return false;

    final customers = await db.query(
      'customers',
      columns: ['id'],
      where: 'uuid = ?',
      whereArgs: [invoice.customerUuid],
      limit: 1,
    );
    if (customers.isEmpty) return false;

    final orders = await db.query(
      'orders',
      columns: ['id'],
      where: 'uuid = ?',
      whereArgs: [invoice.orderUuid],
      limit: 1,
    );
    if (orders.isEmpty) return false;

    final map = invoice
        .copyWith(
          syncStatus: 'synced',
          customerId: customers.first['id'] as int,
          orderId: orders.first['id'] as int,
        )
        .toMap()
      ..remove('id');

    await db.transaction((txn) async {
      int invoiceId;
      if (existing.isEmpty) {
        invoiceId = await txn.insert('invoices', map);
      } else {
        invoiceId = existing.first['id'] as int;
        await txn.update('invoices', map, where: 'id = ?', whereArgs: [invoiceId]);
        await txn.delete(
          'invoice_items',
          where: 'invoice_id = ?',
          whereArgs: [invoiceId],
        );
      }

      for (final item in items) {
        await txn.insert(
          'invoice_items',
          item.toMap()
            ..remove('id')
            ..['invoice_id'] = invoiceId,
        );
      }
    });

    return true;
  }

  Future<void> deleteAll() async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('invoice_items');
      await txn.delete('invoices');
    });
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
