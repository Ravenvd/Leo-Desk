import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/features/customers/models/customer.dart';
import 'package:leo_desk/features/customers/repositories/customer_repository.dart';

Customer makeCustomer({
  required String name,
  String? phone,
  String? whatsapp,
  String? email,
  String? address,
  String? notes,
}) {
  final now = DateTime.now();

  return Customer(
    name: name,
    phone: phone,
    whatsapp: whatsapp,
    email: email,
    address: address,
    notes: notes,
    createdAt: now,
    updatedAt: now,
  );
}

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

  group('CustomerRepository', () {
    test('inserts and retrieves a customer', () async {
      final customer = makeCustomer(
        name: 'Alice',
        phone: '9876543210',
        whatsapp: '9876543210',
        email: 'alice@example.com',
        address: 'Kanyakumari',
        notes: 'Regular customer',
      );

      final id = await repository.insert(customer);

      expect(id, greaterThan(0));

      final savedCustomer = await repository.getById(id);

      expect(savedCustomer, isNotNull);
      expect(savedCustomer!.id, id);
      expect(savedCustomer.name, 'Alice');
      expect(savedCustomer.phone, '9876543210');
      expect(savedCustomer.whatsapp, '9876543210');
      expect(savedCustomer.email, 'alice@example.com');
      expect(savedCustomer.address, 'Kanyakumari');
      expect(savedCustomer.notes, 'Regular customer');
    });

    test('gets all customers ordered by name', () async {
      await repository.insert(
        makeCustomer(
          name: 'Zebra',
        ),
      );

      await repository.insert(
        makeCustomer(
          name: 'Alice',
        ),
      );

      final customers = await repository.getAll();

      expect(customers.length, 2);
      expect(customers[0].name, 'Alice');
      expect(customers[1].name, 'Zebra');
    });

    test('updates a customer', () async {
      final id = await repository.insert(
        makeCustomer(
          name: 'Alice',
          phone: '1111111111',
        ),
      );

      final existing = await repository.getById(id);

      expect(existing, isNotNull);

      final updated = existing!.copyWith(
        name: 'Alice Updated',
        phone: '2222222222',
        notes: 'Updated customer',
      );

      final affectedRows = await repository.update(updated);

      expect(affectedRows, 1);

      final result = await repository.getById(id);

      expect(result, isNotNull);
      expect(result!.name, 'Alice Updated');
      expect(result.phone, '2222222222');
      expect(result.notes, 'Updated customer');
    });

    test('deletes a customer', () async {
      final id = await repository.insert(
        makeCustomer(
          name: 'Alice',
        ),
      );

      final affectedRows = await repository.delete(id);

      expect(affectedRows, 1);

      final result = await repository.getById(id);

      expect(result, isNull);
    });

    test('searches customers by name', () async {
      await repository.insert(
        makeCustomer(
          name: 'Alice Embroidery',
        ),
      );

      await repository.insert(
        makeCustomer(
          name: 'Bob Stitching',
        ),
      );

      final results = await repository.search('Alice');

      expect(results.length, 1);
      expect(results.first.name, 'Alice Embroidery');
    });

    test('searches customers by phone', () async {
      await repository.insert(
        makeCustomer(
          name: 'Alice',
          phone: '9876543210',
        ),
      );

      await repository.insert(
        makeCustomer(
          name: 'Bob',
          phone: '9123456789',
        ),
      );

      final results = await repository.search('9876543210');

      expect(results.length, 1);
      expect(results.first.name, 'Alice');
    });

    test('searches customers by WhatsApp number', () async {
      await repository.insert(
        makeCustomer(
          name: 'Alice',
          whatsapp: '9876543210',
        ),
      );

      await repository.insert(
        makeCustomer(
          name: 'Bob',
          whatsapp: '9123456789',
        ),
      );

      final results = await repository.search('9876543210');

      expect(results.length, 1);
      expect(results.first.name, 'Alice');
    });

    test('searches customers by email', () async {
      await repository.insert(
        makeCustomer(
          name: 'Alice',
          email: 'alice@example.com',
        ),
      );

      await repository.insert(
        makeCustomer(
          name: 'Bob',
          email: 'bob@example.com',
        ),
      );

      final results = await repository.search('alice@example.com');

      expect(results.length, 1);
      expect(results.first.name, 'Alice');
    });

    test('returns all customers when search query is empty', () async {
      await repository.insert(
        makeCustomer(
          name: 'Alice',
        ),
      );

      await repository.insert(
        makeCustomer(
          name: 'Bob',
        ),
      );

      final results = await repository.search('   ');

      expect(results.length, 2);
    });

    test('marks locally inserted customer as pending', () async {
      final customer = makeCustomer(name: 'Local Customer');

      final id = await repository.insert(customer);

      final savedCustomer = await repository.getById(id);

      expect(savedCustomer, isNotNull);
      expect(savedCustomer!.syncStatus, 'pending');
    });
    test('marks customer from sync as synced', () async {
      final customer = makeCustomer(name: 'Synced Customer');

      await repository.upsertFromSync(customer);

      final savedCustomer = await repository.getById(
        (await repository.getAll()).first.id!,
      );

      expect(savedCustomer, isNotNull);
      expect(savedCustomer!.syncStatus, 'synced');
    });
    test('stores business and stitching customer correctly', () async {
      final id = await repository.insert(
        makeCustomer(
          name: 'Leo Designs',
        ),
      );

      final customer = await repository.getById(id);

      expect(customer, isNotNull);
    });
  });
}
