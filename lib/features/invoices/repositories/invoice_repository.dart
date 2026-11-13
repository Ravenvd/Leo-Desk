import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_engine.dart';
import '../../customers/repositories/customer_repository.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';

class InvoiceSyncReconciliation {
  final Invoice invoice;
  final List<InvoiceItem> items;

  const InvoiceSyncReconciliation({
    required this.invoice,
    required this.items,
  });
}

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

  /// Reconciles a pushed invoice on Windows and returns the complete
  /// canonical Windows graph. UUID is checked before relationships or numbers.
  Future<InvoiceSyncReconciliation> reconcileFromSync(
    Invoice incomingInvoice,
    List<InvoiceItem> incomingItems,
  ) async {
    final db = await _db;

    return db.transaction((txn) async {
      final rows = await txn.query('invoices');
      final existingInvoices = rows.map(Invoice.fromMap).toList(growable: false);
      final engine = const SyncEngine();

      final identity = engine.reconcileNumberedRecord<Invoice>(
        incomingRecord: incomingInvoice,
        existingRecords: existingInvoices,
        uuidOf: (record) => record.uuid,
        numberOf: (record) => record.invoiceNumber,
        withCanonicalNumber: (record, number) =>
            record.copyWith(invoiceNumber: number),
      );

      if (!identity.isNewRecord) {
        final canonical = identity.canonicalRecord;
        final itemRows = await txn.query(
          'invoice_items',
          where: 'invoice_id = ?',
          whereArgs: [canonical.id],
          orderBy: 'id ASC',
        );
        return InvoiceSyncReconciliation(
          invoice: canonical,
          items: itemRows.map(InvoiceItem.fromMap).toList(growable: false),
        );
      }

      if (incomingItems.isEmpty) {
        throw StateError('An invoice must contain at least one item.');
      }
      final customerUuid = incomingInvoice.customerUuid;
      if (customerUuid == null || customerUuid.trim().isEmpty) {
        throw StateError('Invoice customer UUID is required.');
      }
      final customers = await txn.query(
        'customers',
        columns: ['id'],
        where: 'uuid = ?',
        whereArgs: [customerUuid],
        limit: 1,
      );
      if (customers.isEmpty) {
        throw StateError('Invoice customer does not exist on Windows.');
      }

      final orders = await txn.query(
        'orders',
        columns: ['id'],
        where: 'uuid = ?',
        whereArgs: [incomingInvoice.orderUuid],
        limit: 1,
      );
      if (orders.isEmpty) {
        throw StateError('Invoice order does not exist on Windows.');
      }

      // The schema permits one invoice per order. A distinct UUID cannot
      // bypass that natural key; preserve the existing graph and reject it.
      final orderOwners = await txn.query(
        'invoices',
        columns: ['uuid'],
        where: 'order_uuid = ? AND uuid != ?',
        whereArgs: [incomingInvoice.orderUuid, incomingInvoice.uuid],
        limit: 1,
      );
      if (orderOwners.isNotEmpty) {
        throw StateError('A different invoice already exists for this order.');
      }

      final incoming = incomingInvoice.copyWith(
        customerId: customers.first['id'] as int,
        orderId: orders.first['id'] as int,
        syncStatus: 'synced',
      );
      final decision = engine.reconcileNumberedRecord<Invoice>(
        incomingRecord: incoming,
        existingRecords: existingInvoices,
        uuidOf: (record) => record.uuid,
        numberOf: (record) => record.invoiceNumber,
        withCanonicalNumber: (record, number) =>
            record.copyWith(invoiceNumber: number),
      );
      final canonical = decision.canonicalRecord;
      final invoiceId = await txn.insert(
        'invoices',
        canonical.toMap()..remove('id'),
      );

      for (final item in incomingItems) {
        await txn.insert(
          'invoice_items',
          item.toMap()
            ..remove('id')
            ..['invoice_id'] = invoiceId,
        );
      }

      final canonicalItems = await txn.query(
        'invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
        orderBy: 'id ASC',
      );
      return InvoiceSyncReconciliation(
        invoice: canonical.copyWith(id: invoiceId, syncStatus: 'synced'),
        items: canonicalItems.map(InvoiceItem.fromMap).toList(growable: false),
      );
    });
  }

  /// Applies a Windows canonical invoice locally. It never deletes a
  /// different UUID to resolve an invoice-number or order collision.
  Future<bool> upsertFromSync(
    Invoice invoice,
    List<InvoiceItem> items, {
    bool force = false,
  }) async {
    final db = await _db;

    return db.transaction((txn) async {
      final existing = await txn.query(
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

      final customers = await txn.query(
        'customers',
        columns: ['id'],
        where: 'uuid = ?',
        whereArgs: [invoice.customerUuid],
        limit: 1,
      );
      if (customers.isEmpty) return false;

      final orders = await txn.query(
        'orders',
        columns: ['id'],
        where: 'uuid = ?',
        whereArgs: [invoice.orderUuid],
        limit: 1,
      );
      if (orders.isEmpty) return false;

      final numberOwners = await txn.query(
        'invoices',
        columns: ['uuid'],
        where: 'invoice_number = ? AND uuid != ?',
        whereArgs: [invoice.invoiceNumber, invoice.uuid],
        limit: 1,
      );
      if (numberOwners.isNotEmpty) return false;

      final orderOwners = await txn.query(
        'invoices',
        columns: ['uuid'],
        where: 'order_uuid = ? AND uuid != ?',
        whereArgs: [invoice.orderUuid, invoice.uuid],
        limit: 1,
      );
      if (orderOwners.isNotEmpty) return false;

      final map = invoice.copyWith(
        syncStatus: 'synced',
        customerId: customers.first['id'] as int,
        orderId: orders.first['id'] as int,
      ).toMap()..remove('id');

      late final int invoiceId;
      if (existing.isEmpty) {
        invoiceId = await txn.insert('invoices', map);
      } else {
        invoiceId = existing.first['id'] as int;
        await txn.update(
          'invoices',
          map,
          where: 'id = ?',
          whereArgs: [invoiceId],
        );
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
