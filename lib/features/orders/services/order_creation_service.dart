import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../models/order.dart';
import '../models/order_item.dart';

class OrderItemDraft {
  final String workType;
  final String garmentType;
  final int quantity;
  final int unitPricePaise;
  final String? notes;

  const OrderItemDraft({
    required this.workType,
    required this.garmentType,
    required this.quantity,
    required this.unitPricePaise,
    this.notes,
  });
}

class OrderCreationService {
  final Database? database;

  OrderCreationService({this.database});

  Future<Database> get _db async {
    return database ?? await AppDatabase.database;
  }

  Future<Order> create({
    required int customerId,
    required bool stitchingRequired,
    required List<OrderItemDraft> items,
    String? notes,
    DateTime? now,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('An order must contain at least one item.');
    }

    for (final item in items) {
      if (item.quantity <= 0) {
        throw ArgumentError('Order item quantity must be greater than zero.');
      }
      if (item.unitPricePaise < 0) {
        throw ArgumentError('Order item price cannot be negative.');
      }
    }

    final db = await _db;
    final createdAt = now ?? DateTime.now();
    final expectedDeliveryDate = createdAt.add(
      Duration(hours: stitchingRequired ? 120 : 72),
    );

    return db.transaction((txn) async {
      final customer = await txn.query(
        'customers',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [customerId],
        limit: 1,
      );

      if (customer.isEmpty) {
        throw ArgumentError('Customer does not exist.');
      }

      final orderNumber = await _nextOrderNumber(txn);

      final order = Order(
        orderNumber: orderNumber,
        customerId: customerId,
        orderDate: createdAt,
        expectedDeliveryDate: expectedDeliveryDate,
        stitchingRequired: stitchingRequired,
        status: 'New',
        notes: notes,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      final orderId = await txn.insert(
        'orders',
        order.toMap()..remove('id'),
      );

      for (final draft in items) {
        final item = OrderItem(
          orderId: orderId,
          workType: draft.workType,
          garmentType: draft.garmentType,
          quantity: draft.quantity,
          unitPricePaise: draft.unitPricePaise,
          notes: draft.notes,
          createdAt: createdAt,
          updatedAt: createdAt,
        );

        await txn.insert(
          'order_items',
          item.toMap()..remove('id'),
        );
      }

      return order.copyWith(id: orderId);
    });
  }

  Future<String> _nextOrderNumber(Transaction txn) async {
    final result = await txn.rawQuery(
      "SELECT MAX(CAST(SUBSTR(order_number, 5) AS INTEGER)) AS last_number "
      "FROM orders WHERE order_number LIKE 'ORD-%'",
    );

    final lastNumber = result.first['last_number'] as int? ?? 0;
    return 'ORD-\${(lastNumber + 1).toString().padLeft(6, '0')}';
  }
}