import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/features/billing/models/bill.dart';
import 'package:leo_desk/features/billing/models/bill_item.dart';
import 'package:leo_desk/features/billing/repositories/bill_repository.dart';
import 'package:leo_desk/features/customers/models/customer.dart';
import 'package:leo_desk/features/customers/repositories/customer_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database database;
  late CustomerRepository customerRepository;
  late BillRepository billRepository;

  setUp(() async {
    database = await AppDatabase.openTestDatabase();
    customerRepository = CustomerRepository(database: database);
    billRepository = BillRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  test('inserts a bill with items and retrieves it', () async {
    final now = DateTime.now();

    final customerId = await customerRepository.insert(
      Customer(
        name: 'Alice',
        createdAt: now,
        updatedAt: now,
        customerType: 'personal',
        serviceRequired: 'embroidery',
      ),
    );

    final bill = Bill(
      customerId: customerId,
      billNumber: 'INV-0001',
      billDate: now,
      subtotalPaise: 300000,
      totalPaise: 300000,
      createdAt: now,
      updatedAt: now,
    );

    final billId = await billRepository.insert(
      bill: bill,
      items: [
        BillItem(
          billId: 0,
          description: 'Logo embroidery',
          quantity: 20,
          ratePaise: 15000,
          amountPaise: 300000,
        ),
      ],
    );

    final savedBill = await billRepository.getById(billId);
    final items = await billRepository.getItems(billId);

    expect(savedBill, isNotNull);
    expect(savedBill!.customerId, customerId);
    expect(savedBill.billNumber, 'INV-0001');
    expect(savedBill.totalPaise, 300000);

    expect(items.length, 1);
    expect(items.first.description, 'Logo embroidery');
    expect(items.first.quantity, 20);
    expect(items.first.amountPaise, 300000);
  });

  test('gets bills for a customer newest first', () async {
    final now = DateTime.now();

    final customerId = await customerRepository.insert(
      Customer(
        name: 'Alice',
        createdAt: now,
        updatedAt: now,
        customerType: 'personal',
        serviceRequired: 'embroidery',
      ),
    );

    final firstDate = now.subtract(const Duration(days: 2));

    await billRepository.insert(
      bill: Bill(
        customerId: customerId,
        billNumber: 'INV-0001',
        billDate: firstDate,
        subtotalPaise: 10000,
        totalPaise: 10000,
        createdAt: firstDate,
        updatedAt: firstDate,
      ),
      items: [
        BillItem(
          billId: 0,
          description: 'Stitching',
          quantity: 1,
          ratePaise: 10000,
          amountPaise: 10000,
        ),
      ],
    );

    await billRepository.insert(
      bill: Bill(
        customerId: customerId,
        billNumber: 'INV-0002',
        billDate: now,
        subtotalPaise: 20000,
        totalPaise: 20000,
        createdAt: now,
        updatedAt: now,
      ),
      items: [
        BillItem(
          billId: 0,
          description: 'Embroidery',
          quantity: 1,
          ratePaise: 20000,
          amountPaise: 20000,
        ),
      ],
    );

    final bills = await billRepository.getForCustomer(customerId);

    expect(bills.length, 2);
    expect(bills[0].billNumber, 'INV-0002');
    expect(bills[1].billNumber, 'INV-0001');
  });

  test('calculates payment status', () {
    final now = DateTime.now();

    final unpaid = Bill(
      customerId: 1,
      billNumber: 'INV-1',
      billDate: now,
      subtotalPaise: 10000,
      totalPaise: 10000,
      createdAt: now,
      updatedAt: now,
    );

    final partial = unpaid.copyWith(amountPaidPaise: 5000);
    final paid = unpaid.copyWith(amountPaidPaise: 10000);

    expect(unpaid.paymentStatus, 'unpaid');
    expect(partial.paymentStatus, 'partial');
    expect(paid.paymentStatus, 'paid');
    expect(partial.balanceDuePaise, 5000);
  });
}
