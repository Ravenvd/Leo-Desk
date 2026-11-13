import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../customers/repositories/customer_repository.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';

class InvoiceRepository {
  final Database? database;
  final bool isNumberAuthority;

  /// Invoice numbers are derived from the canonical Windows order number.
  InvoiceRepository({this.database, bool? isNumberAuthority})
      : isNumberAuthority = isNumberAuthority ?? Platform.isWindows;

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
      columns: ['id', 'order_number'],
      where: 'uuid = ?',
      whereArgs: [invoice.orderUuid],
      limit: 1,
    );
    if (orders.isEmpty) return false;

    final canonicalInvoice = isNumberAuthority
        ? invoice.copyWith(
            invoiceNumber: _canonicalInvoiceNumber(
              orders.first['order_number'] as String,
            ),
          )
        : invoice;
    final map = canonicalInvoice
        .copyWith(
          syncStatus: 'synced',
          customerId: customers.first['id'] as int,
          orderId: orders.first['id'] as int,
        )
        .toMap()
      ..remove('id');

    return db.transaction((txn) async {
      final sameUuid = await txn.query(
        'invoices',
        columns: ['id', 'sync_status'],
        where: 'uuid = ?',
        whereArgs: [invoice.uuid],
        limit: 1,
      );
      if (!force &&
          sameUuid.isNotEmpty &&
          sameUuid.first['sync_status'] == 'pending') {
        return false;
      }

      // An order can have only one invoice. Do not replace an unsynced local
      // invoice; wait until its push has been resolved. Stale synced copies
      // may be replaced by the canonical Windows UUID.
      final orderConflicts = await txn.query(
        'invoices',
        columns: ['id', 'uuid', 'sync_status'],
        where: 'order_uuid = ? AND uuid != ?',
        whereArgs: [invoice.orderUuid, invoice.uuid],
      );
      if (!force &&
          orderConflicts.any((row) => row['sync_status'] == 'pending')) {
        return false;
      }
      for (final conflict in orderConflicts) {
        final conflictId = conflict['id'] as int;
        await txn.delete(
          'invoice_items',
          where: 'invoice_id = ?',
          whereArgs: [conflictId],
        );
        await txn.delete('invoices', where: 'id = ?', whereArgs: [conflictId]);
      }

      // Free a legacy/client-generated number collision without deleting the
      // unrelated invoice. Its own canonical copy can assign the final number
      // when it is pulled.
      final numberOwners = await txn.query(
        'invoices',
        columns: ['id', 'uuid', 'sync_status'],
        where: 'invoice_number = ? AND uuid != ?',
        whereArgs: [canonicalInvoice.invoiceNumber, invoice.uuid],
      );
      if (!force &&
          numberOwners.any((row) => row['sync_status'] == 'pending')) {
        return false;
      }
      for (final owner in numberOwners) {
        await txn.update(
          'invoices',
          {'invoice_number': 'PENDING-${owner['uuid']}'},
          where: 'id = ?',
          whereArgs: [owner['id']],
        );
      }

      int invoiceId;
      if (sameUuid.isEmpty) {
        invoiceId = await txn.insert('invoices', map);
      } else {
        invoiceId = sameUuid.first['id'] as int;
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

      return true;
    });

  }

  String _canonicalInvoiceNumber(String orderNumber) {
    final suffix = orderNumber.startsWith('ORD-')
        ? orderNumber.substring(4)
        : orderNumber;
    return 'INV-$suffix';
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
