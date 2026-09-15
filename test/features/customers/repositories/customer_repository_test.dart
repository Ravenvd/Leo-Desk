import 'package:flutter_test/flutter_test.dart';
import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/features/customers/models/customer.dart';
import 'package:leo_desk/features/customers/repositories/customer_repository.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  late Database database;
  late CustomerRepository repository;

  setUp(() async {
    database = await AppDatabase.openTestDatabase();
    repository = CustomerRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  Customer makeCustomer({
    required String uuid,
    required String name,
    String syncStatus = 'synced',
  }) {
    final now = DateTime.utc(2026, 1, 1);
    return Customer(
      uuid: uuid,
      syncStatus: syncStatus,
      name: name,
      phone: '9876543210',
      whatsapp: '9876543210',
      email: 'test@example.com',
      address: 'Test address',
      notes: 'Test notes',
      createdAt: now,
      updatedAt: now,
      customerType: 'Individual',
      serviceRequired: 'Embroidery',
    );
  }

  test('inserts a new customer received from sync as synced', () async {
    final incoming = makeCustomer(uuid: 'customer-1', name: 'Alice');

    final applied = await repository.upsertFromSync(incoming);

    expect(applied, isTrue);

    final customers = await repository.getAll();
    expect(customers, hasLength(1));
    expect(customers.single.uuid, 'customer-1');
    expect(customers.single.name, 'Alice');
    expect(customers.single.syncStatus, 'synced');
  });

  test('updates an existing synced customer without creating a duplicate', () async {
    final original = makeCustomer(uuid: 'customer-2', name: 'Alice');
    await database.insert('customers', original.toMap()..remove('id'));

    final incoming = makeCustomer(uuid: 'customer-2', name: 'Alice Updated');

    final applied = await repository.upsertFromSync(incoming);

    expect(applied, isTrue);

    final customers = await repository.getAll();
    expect(customers, hasLength(1));
    expect(customers.single.uuid, 'customer-2');
    expect(customers.single.name, 'Alice Updated');
    expect(customers.single.syncStatus, 'synced');
  });

  test('rejects an incoming customer when the local customer is pending', () async {
    final local = makeCustomer(
      uuid: 'customer-3',
      name: 'Local Version',
      syncStatus: 'pending',
    );
    await database.insert('customers', local.toMap()..remove('id'));

    final incoming = makeCustomer(uuid: 'customer-3', name: 'Server Version');

    final applied = await repository.upsertFromSync(incoming);

    expect(applied, isFalse);

    final customers = await repository.getAll();
    expect(customers, hasLength(1));
    expect(customers.single.name, 'Local Version');
    expect(customers.single.syncStatus, 'pending');
  });

  test('pulling a server customer creates a synced local customer', () async {
    final incoming = makeCustomer(uuid: 'customer-4', name: 'Pulled Customer');

    final applied = await repository.upsertFromSync(incoming);

    expect(applied, isTrue);

    final customer = (await repository.getAll()).single;
    expect(customer.uuid, 'customer-4');
    expect(customer.name, 'Pulled Customer');
    expect(customer.syncStatus, 'synced');
  });
}
