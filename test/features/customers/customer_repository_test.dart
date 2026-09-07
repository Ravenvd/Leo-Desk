import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:leo_desk/features/customers/models/customer.dart';
import 'package:leo_desk/features/customers/repositories/customer_repository.dart';
import 'package:leo_desk/core/database/app_database.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Database database;
  late CustomerRepository repository;

  setUp(() async {
    database = await AppDatabase.openTestDatabase();
    repository = CustomerRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  Customer createCustomer({
    String name = 'Test Customer',
    String phone = '9876543210',
  }) {
    final now = DateTime.now();

    return Customer(
      name: name,
      phone: phone,
      whatsapp: phone,
      email: 'test@example.com',
      address: 'Test Address',
      notes: 'Test Notes',
      createdAt: now,
      updatedAt: now,
    );
  }

  test('inserts and retrieves a customer', () async {
    final customer = createCustomer();

    final id = await repository.insert(customer);

    expect(id, greaterThan(0));

    final retrieved = await repository.getById(id);

    expect(retrieved, isNotNull);
    expect(retrieved!.id, id);
    expect(retrieved.name, 'Test Customer');
    expect(retrieved.phone, '9876543210');
  });

  test('gets all customers ordered by name', () async {
    await repository.insert(createCustomer(name: 'Zebra'));
    await repository.insert(createCustomer(name: 'Alpha'));

    final customers = await repository.getAll();

    expect(customers.length, 2);
    expect(customers[0].name, 'Alpha');
    expect(customers[1].name, 'Zebra');
  });

  test('searches customers by name', () async {
    await repository.insert(
      createCustomer(name: 'John Embroidery'),
    );

    await repository.insert(
      createCustomer(name: 'Mary Textiles'),
    );

    final results = await repository.search('Embroidery');

    expect(results.length, 1);
    expect(results.first.name, 'John Embroidery');
  });

  test('searches customers by phone', () async {
    await repository.insert(
      createCustomer(
        name: 'John',
        phone: '9999999999',
      ),
    );

    final results = await repository.search('9999999999');

    expect(results.length, 1);
    expect(results.first.name, 'John');
  });

  test('updates a customer', () async {
    final id = await repository.insert(
      createCustomer(name: 'Original Name'),
    );

    final original = await repository.getById(id);

    final updated = original!.copyWith(
      name: 'Updated Name',
      phone: '8888888888',
      updatedAt: DateTime.now(),
    );

    final rows = await repository.update(updated);

    expect(rows, 1);

    final result = await repository.getById(id);

    expect(result!.name, 'Updated Name');
    expect(result.phone, '8888888888');
  });

  test('deletes a customer', () async {
    final id = await repository.insert(
      createCustomer(),
    );

    final rows = await repository.delete(id);

    expect(rows, 1);

    final result = await repository.getById(id);

    expect(result, isNull);
  });
}