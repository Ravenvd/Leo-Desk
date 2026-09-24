import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/features/customers/models/customer.dart';
import 'package:leo_desk/features/customers/repositories/customer_repository.dart';
import 'package:leo_desk/features/orders/models/order.dart';
import 'package:leo_desk/features/orders/models/order_item.dart';
import 'package:leo_desk/features/orders/repositories/order_item_repository.dart';
import 'package:leo_desk/features/orders/repositories/order_repository.dart';

Order makeOrder({required int customerId, String orderNumber = 'ORD-000001'}) {
  final now = DateTime.now();

  return Order(
    orderNumber: orderNumber,
    customerId: customerId,
    orderDate: now,
    expectedDeliveryDate: now.add(const Duration(hours: 72)),
    stitchingRequired: false,
    createdAt: now,
    updatedAt: now,
  );
}

OrderItem makeItem({
  required int orderId,
  String workType = 'Embroidery',
  String garmentType = 'Blouse',
  int quantity = 2,
  int unitPricePaise = 15000,
  String? notes,
}) {
  final now = DateTime.now();

  return OrderItem(
    orderId: orderId,
    workType: workType,
    garmentType: garmentType,
    quantity: quantity,
    unitPricePaise: unitPricePaise,
    notes: notes,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database database;
  late OrderRepository orderRepository;
  late OrderItemRepository repository;
  late CustomerRepository customerRepository;

  setUp(() async {
    database = await AppDatabase.openTestDatabase();
    orderRepository = OrderRepository(database: database);
    repository = OrderItemRepository(database: database);
    customerRepository = CustomerRepository(database: database);

    final now = DateTime.now();
    await customerRepository.insert(
      Customer(
        name: 'Test Customer',
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('OrderItemRepository', () {
    test('inserts and retrieves an order item', () async {
      final orderId = await orderRepository.insert(
        makeOrder(customerId: 1),
      );

      final item = makeItem(
        orderId: orderId,
        notes: 'Test item',
      );

      final id = await repository.insert(item);

      expect(id, greaterThan(0));

      final savedItem = await repository.getById(id);

      expect(savedItem, isNotNull);
      expect(savedItem!.id, id);
      expect(savedItem.orderId, orderId);
      expect(savedItem.workType, 'Embroidery');
      expect(savedItem.garmentType, 'Blouse');
      expect(savedItem.quantity, 2);
      expect(savedItem.unitPricePaise, 15000);
      expect(savedItem.notes, 'Test item');
    });

    test('gets items for an order in insertion order', () async {
      final orderId = await orderRepository.insert(
        makeOrder(customerId: 1),
      );

      await repository.insert(
        makeItem(
          orderId: orderId,
          workType: 'Embroidery',
          garmentType: 'Blouse',
        ),
      );
      await repository.insert(
        makeItem(
          orderId: orderId,
          workType: 'Aari',
          garmentType: 'Garment piece',
        ),
      );

      final items = await repository.getByOrder(orderId);

      expect(items.length, 2);
      expect(items[0].workType, 'Embroidery');
      expect(items[0].garmentType, 'Blouse');
      expect(items[1].workType, 'Aari');
      expect(items[1].garmentType, 'Garment piece');
    });

    test('does not return items belonging to another order', () async {
      final firstOrderId = await orderRepository.insert(
        makeOrder(
          customerId: 1,
          orderNumber: 'ORD-000001',
        ),
      );
      final secondOrderId = await orderRepository.insert(
        makeOrder(
          customerId: 1,
          orderNumber: 'ORD-000002',
        ),
      );

      await repository.insert(makeItem(orderId: firstOrderId));
      await repository.insert(makeItem(orderId: secondOrderId));

      final items = await repository.getByOrder(firstOrderId);

      expect(items.length, 1);
      expect(items.first.orderId, firstOrderId);
    });

    test('updates an order item', () async {
      final orderId = await orderRepository.insert(
        makeOrder(customerId: 1),
      );

      final id = await repository.insert(
        makeItem(orderId: orderId),
      );

      final existing = await repository.getById(id);

      expect(existing, isNotNull);

      final updated = existing!.copyWith(
        workType: 'Aari',
        garmentType: 'Garment piece',
        quantity: 5,
        unitPricePaise: 20000,
        notes: 'Updated item',
      );

      final affectedRows = await repository.update(updated);

      expect(affectedRows, 1);

      final result = await repository.getById(id);

      expect(result, isNotNull);
      expect(result!.workType, 'Aari');
      expect(result.garmentType, 'Garment piece');
      expect(result.quantity, 5);
      expect(result.unitPricePaise, 20000);
      expect(result.notes, 'Updated item');
    });

    test('rejects updating an order item without an id', () async {
      final orderId = await orderRepository.insert(
        makeOrder(customerId: 1),
      );

      final item = makeItem(orderId: orderId);

      expect(
        () => repository.update(item),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('deletes an order item', () async {
      final orderId = await orderRepository.insert(
        makeOrder(customerId: 1),
      );

      final id = await repository.insert(
        makeItem(orderId: orderId),
      );

      final affectedRows = await repository.delete(id);

      expect(affectedRows, 1);
      expect(await repository.getById(id), isNull);
    });

    test('deleteByOrder removes only items for the selected order', () async {
      final firstOrderId = await orderRepository.insert(
        makeOrder(
          customerId: 1,
          orderNumber: 'ORD-000001',
        ),
      );
      final secondOrderId = await orderRepository.insert(
        makeOrder(
          customerId: 1,
          orderNumber: 'ORD-000002',
        ),
      );

      await repository.insert(makeItem(orderId: firstOrderId));
      await repository.insert(makeItem(orderId: firstOrderId));
      await repository.insert(makeItem(orderId: secondOrderId));

      await repository.deleteByOrder(firstOrderId);

      expect(await repository.getByOrder(firstOrderId), isEmpty);

      final remaining = await repository.getByOrder(secondOrderId);
      expect(remaining.length, 1);
    });

    test('cascades item deletion when the parent order is deleted', () async {
      final orderId = await orderRepository.insert(
        makeOrder(customerId: 1),
      );

      await repository.insert(makeItem(orderId: orderId));

      await orderRepository.delete(orderId);

      expect(await repository.getByOrder(orderId), isEmpty);
    });
  });
}
