import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/features/customers/models/customer.dart';
import 'package:leo_desk/features/customers/repositories/customer_repository.dart';
import 'package:leo_desk/features/orders/models/order.dart';
import 'package:leo_desk/features/orders/repositories/order_repository.dart';

Order makeOrder({
  required int customerId,
  String orderNumber = 'ORD-000001',
  bool stitchingRequired = false,
  String status = 'New',
  String? notes,
  DateTime? createdAt,
}) {
  final created = createdAt ?? DateTime.now();

  return Order(
    orderNumber: orderNumber,
    customerId: customerId,
    orderDate: created,
    expectedDeliveryDate: created.add(
      Duration(hours: stitchingRequired ? 120 : 72),
    ),
    stitchingRequired: stitchingRequired,
    status: status,
    notes: notes,
    createdAt: created,
    updatedAt: created,
  );
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database database;
  late OrderRepository repository;
  late CustomerRepository customerRepository;

  setUp(() async {
    database = await AppDatabase.openTestDatabase();
    repository = OrderRepository(database: database);
    customerRepository = CustomerRepository(database: database);

    final now = DateTime.now();
    await customerRepository.insert(
      Customer(
        name: 'Test Customer 1',
        createdAt: now,
        updatedAt: now,
        customerType: 'personal',
        serviceRequired: 'embroidery',
      ),
    );
    await customerRepository.insert(
      Customer(
        name: 'Test Customer 2',
        createdAt: now,
        updatedAt: now,
        customerType: 'business',
        serviceRequired: 'stitching',
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('OrderRepository', () {
    test('inserts and retrieves an order', () async {
      final order = makeOrder(
        customerId: 1,
        orderNumber: 'ORD-000001',
        notes: 'Test order',
      );

      final id = await repository.insert(order);

      expect(id, greaterThan(0));

      final savedOrder = await repository.getById(id);

      expect(savedOrder, isNotNull);
      expect(savedOrder!.id, id);
      expect(savedOrder.orderNumber, 'ORD-000001');
      expect(savedOrder.customerId, 1);
      expect(savedOrder.stitchingRequired, false);
      expect(savedOrder.status, 'New');
      expect(savedOrder.notes, 'Test order');
      expect(savedOrder.syncStatus, 'pending');
    });

    test('gets all orders newest first', () async {
      final older = makeOrder(
        customerId: 1,
        orderNumber: 'ORD-000001',
        createdAt: DateTime(2026, 1, 1),
      );
      final newer = makeOrder(
        customerId: 1,
        orderNumber: 'ORD-000002',
        createdAt: DateTime(2026, 1, 2),
      );

      await repository.insert(older);
      await repository.insert(newer);

      final orders = await repository.getAll();

      expect(orders.length, 2);
      expect(orders[0].orderNumber, 'ORD-000002');
      expect(orders[1].orderNumber, 'ORD-000001');
    });

    test('gets orders for a specific customer', () async {
      await repository.insert(
        makeOrder(
          customerId: 1,
          orderNumber: 'ORD-000001',
        ),
      );
      await repository.insert(
        makeOrder(
          customerId: 2,
          orderNumber: 'ORD-000002',
        ),
      );
      await repository.insert(
        makeOrder(
          customerId: 1,
          orderNumber: 'ORD-000003',
        ),
      );

      final orders = await repository.getByCustomer(1);

      expect(orders.length, 2);
      expect(
        orders.map((order) => order.orderNumber),
        containsAll(['ORD-000001', 'ORD-000003']),
      );
      expect(orders.every((order) => order.customerId == 1), isTrue);
    });

    test('updates an order and marks it pending', () async {
      final id = await repository.insert(
        makeOrder(
          customerId: 1,
          orderNumber: 'ORD-000001',
        ),
      );

      final existing = await repository.getById(id);

      expect(existing, isNotNull);

      final updated = existing!.copyWith(
        status: 'In Progress',
        notes: 'Updated order',
      );

      final affectedRows = await repository.update(updated);

      expect(affectedRows, 1);

      final result = await repository.getById(id);

      expect(result, isNotNull);
      expect(result!.status, 'In Progress');
      expect(result.notes, 'Updated order');
      expect(result.syncStatus, 'pending');
    });

    test('rejects updating an order without an id', () async {
      final order = makeOrder(customerId: 1);

      expect(
        () => repository.update(order),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('deletes an order', () async {
      final id = await repository.insert(
        makeOrder(customerId: 1),
      );

      final affectedRows = await repository.delete(id);

      expect(affectedRows, 1);
      expect(await repository.getById(id), isNull);
    });

    test('gets only pending orders', () async {
      final order = makeOrder(customerId: 1);

      await repository.insert(order);

      final pending = await repository.getPending();

      expect(pending.length, 1);
      expect(pending.first.uuid, order.uuid);
      expect(pending.first.syncStatus, 'pending');
    });

    test('marks an order as synced', () async {
      final order = makeOrder(customerId: 1);
      final id = await repository.insert(order);

      final affectedRows = await repository.markSynced(order.uuid);

      expect(affectedRows, 1);

      final savedOrder = await repository.getById(id);

      expect(savedOrder, isNotNull);
      expect(savedOrder!.syncStatus, 'synced');
      expect(await repository.getPending(), isEmpty);
    });

    test('upserts a new order from sync as synced', () async {
      final order = makeOrder(
        customerId: 1,
        orderNumber: 'ORD-000001',
      );

      final applied = await repository.upsertFromSync(order, const []);

      expect(applied, true);

      final orders = await repository.getAll();

      expect(orders.length, 1);
      expect(orders.first.uuid, order.uuid);
      expect(orders.first.orderNumber, 'ORD-000001');
      expect(orders.first.syncStatus, 'synced');
    });

    test('updates an existing synced order from sync', () async {
      final order = makeOrder(
        customerId: 1,
        orderNumber: 'ORD-000001',
      );

      await repository.upsertFromSync(order, const []);

      final serverUpdate = order.copyWith(
        status: 'Ready',
        notes: 'Updated by server',
        updatedAt: DateTime.now(),
      );

      final applied = await repository.upsertFromSync(serverUpdate, const []);

      expect(applied, true);

      final orders = await repository.getAll();

      expect(orders.length, 1);
      expect(orders.first.status, 'Ready');
      expect(orders.first.notes, 'Updated by server');
      expect(orders.first.syncStatus, 'synced');
    });

    test('does not overwrite a locally pending order during sync', () async {
      final localOrder = makeOrder(
        customerId: 1,
        orderNumber: 'ORD-000001',
        notes: 'Local change',
      );

      await repository.insert(localOrder);

      final serverOrder = localOrder.copyWith(
        status: 'Ready',
        notes: 'Server version',
        updatedAt: DateTime.now(),
      );

      final applied = await repository.upsertFromSync(serverOrder);

      expect(applied, false);

      final savedOrder = await repository.getById(
        (await repository.getAll()).first.id!,
      );

      expect(savedOrder, isNotNull);
      expect(savedOrder!.status, 'New');
      expect(savedOrder.notes, 'Local change');
      expect(savedOrder.syncStatus, 'pending');
    });

    test('deleteAll removes every order', () async {
      await repository.insert(
        makeOrder(
          customerId: 1,
          orderNumber: 'ORD-000001',
        ),
      );
      await repository.insert(
        makeOrder(
          customerId: 2,
          orderNumber: 'ORD-000002',
        ),
      );

      await repository.deleteAll();

      expect(await repository.getAll(), isEmpty);
    });
  });
}
