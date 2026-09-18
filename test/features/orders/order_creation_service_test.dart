import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/features/customers/models/customer.dart';
import 'package:leo_desk/features/customers/repositories/customer_repository.dart';
import 'package:leo_desk/features/orders/repositories/order_item_repository.dart';
import 'package:leo_desk/features/orders/repositories/order_repository.dart';
import 'package:leo_desk/features/orders/services/order_creation_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database database;
  late CustomerRepository customerRepository;
  late OrderRepository orderRepository;
  late OrderItemRepository itemRepository;
  late OrderCreationService service;

  setUp(() async {
    database = await AppDatabase.openTestDatabase();
    customerRepository = CustomerRepository(database: database);
    orderRepository = OrderRepository(database: database);
    itemRepository = OrderItemRepository(database: database);
    service = OrderCreationService(database: database);

    final now = DateTime.now();
    await customerRepository.insert(
      Customer(
        name: 'Test Customer',
        createdAt: now,
        updatedAt: now,
        customerType: 'personal',
        serviceRequired: 'embroidery',
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('creates an order with 72-hour delivery and its items', () async {
    final now = DateTime(2026, 7, 1, 10);

    final order = await service.create(
      customerId: 1,
      stitchingRequired: false,
      now: now,
      notes: 'Rush order',
      items: const [
        OrderItemDraft(
          workType: 'Embroidery',
          garmentType: 'Blouse',
          quantity: 2,
          unitPricePaise: 15000,
          notes: 'Front design',
        ),
        OrderItemDraft(
          workType: 'Aari',
          garmentType: 'Garment piece',
          quantity: 1,
          unitPricePaise: 25000,
        ),
      ],
    );

    expect(order.id, 1);
    expect(order.orderNumber, 'ORD-000001');
    expect(order.customerId, 1);
    expect(order.orderDate, now);
    expect(order.expectedDeliveryDate, now.add(const Duration(hours: 72)));
    expect(order.stitchingRequired, false);
    expect(order.status, 'New');
    expect(order.notes, 'Rush order');
    expect(order.syncStatus, 'pending');

    final items = await itemRepository.getByOrder(order.id!);

    expect(items.length, 2);
    expect(items[0].workType, 'Embroidery');
    expect(items[0].quantity, 2);
    expect(items[0].unitPricePaise, 15000);
    expect(items[1].workType, 'Aari');
    expect(items[1].garmentType, 'Garment piece');
  });

  test('uses 120-hour delivery when stitching is required', () async {
    final now = DateTime(2026, 7, 1, 10);

    final order = await service.create(
      customerId: 1,
      stitchingRequired: true,
      stitchingPricePaise: 50000,
      now: now,
      items: const [
        OrderItemDraft(
          workType: 'Embroidery',
          garmentType: 'Blouse',
          quantity: 1,
          unitPricePaise: 10000,
        ),
      ],
    );

    expect(order.expectedDeliveryDate, now.add(const Duration(hours: 120)));
    expect(order.stitchingRequired, true);
    expect(order.stitchingPricePaise, 50000);
  });


  test('rejects negative stitching price', () async {
    expect(
      () => service.create(
        customerId: 1,
        stitchingRequired: true,
        stitchingPricePaise: -1,
        items: const [
          OrderItemDraft(
            workType: 'Embroidery',
            garmentType: 'Blouse',
            quantity: 1,
            unitPricePaise: 10000,
          ),
        ],
      ),
      throwsA(isA<ArgumentError>()),
    );

    expect(await orderRepository.getAll(), isEmpty);
  });

  test('generates the next order number from existing orders', () async {
    final first = await service.create(
      customerId: 1,
      stitchingRequired: false,
      items: const [
        OrderItemDraft(
          workType: 'Embroidery',
          garmentType: 'Blouse',
          quantity: 1,
          unitPricePaise: 10000,
        ),
      ],
    );
    final second = await service.create(
      customerId: 1,
      stitchingRequired: false,
      items: const [
        OrderItemDraft(
          workType: 'Aari',
          garmentType: 'Garment piece',
          quantity: 1,
          unitPricePaise: 20000,
        ),
      ],
    );

    expect(first.orderNumber, 'ORD-000001');
    expect(second.orderNumber, 'ORD-000002');
  });

  test('rejects an order without items', () async {
    expect(
      () => service.create(
        customerId: 1,
        stitchingRequired: false,
        items: const [],
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects an unknown customer', () async {
    expect(
      () => service.create(
        customerId: 999,
        stitchingRequired: false,
        items: const [
          OrderItemDraft(
            workType: 'Embroidery',
            garmentType: 'Blouse',
            quantity: 1,
            unitPricePaise: 10000,
          ),
        ],
      ),
      throwsA(isA<ArgumentError>()),
    );

    expect(await orderRepository.getAll(), isEmpty);
  });

  test('rejects zero or negative item quantity', () async {
    expect(
      () => service.create(
        customerId: 1,
        stitchingRequired: false,
        items: const [
          OrderItemDraft(
            workType: 'Embroidery',
            garmentType: 'Blouse',
            quantity: 0,
            unitPricePaise: 10000,
          ),
        ],
      ),
      throwsA(isA<ArgumentError>()),
    );

    expect(await orderRepository.getAll(), isEmpty);
  });

  test('rejects negative item price', () async {
    expect(
      () => service.create(
        customerId: 1,
        stitchingRequired: false,
        items: const [
          OrderItemDraft(
            workType: 'Embroidery',
            garmentType: 'Blouse',
            quantity: 1,
            unitPricePaise: -1,
          ),
        ],
      ),
      throwsA(isA<ArgumentError>()),
    );

    expect(await orderRepository.getAll(), isEmpty);
  });
}