import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/features/billing/models/bill.dart';
import 'package:leo_desk/features/billing/models/bill_item.dart';
import 'package:leo_desk/features/billing/repositories/bill_repository.dart';
import 'package:leo_desk/features/customers/models/customer.dart';
import 'package:leo_desk/features/customers/repositories/customer_repository.dart';
import 'package:leo_desk/features/dashboard/screens/dashboard_screen.dart';
import 'package:leo_desk/features/expenses/repositories/expense_repository.dart';
import 'package:leo_desk/features/invoices/repositories/invoice_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database database;
  late CustomerRepository customerRepository;
  late BillRepository billRepository;
  late ExpenseRepository expenseRepository;
  late InvoiceRepository invoiceRepository;

  setUp(() async {
    database = await AppDatabase.openTestDatabase();
    customerRepository = CustomerRepository(database: database);
    billRepository = BillRepository(database: database);
    expenseRepository = ExpenseRepository(database: database);
    invoiceRepository = InvoiceRepository(database: database);

    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1, 5);

    final aliceId = await customerRepository.insert(
      Customer(
        name: 'Alice',
        createdAt: lastMonth,
        updatedAt: lastMonth,
        customerType: 'personal',
        serviceRequired: 'embroidery',
      ),
    );
    await database.update(
      'customers',
      {'created_at': lastMonth.toIso8601String()},
      where: 'id = ?',
      whereArgs: [aliceId],
    );

    await customerRepository.insert(
      Customer(
        name: 'Bob',
        createdAt: now,
        updatedAt: now,
        customerType: 'business',
        serviceRequired: 'stitching',
      ),
    );

    Future<void> addBill(
      int customerId,
      String number,
      DateTime date,
      int totalPaise,
    ) {
      return billRepository.insert(
        bill: Bill(
          customerId: customerId,
          billNumber: number,
          billDate: date,
          subtotalPaise: totalPaise,
          totalPaise: totalPaise,
          amountPaidPaise: totalPaise,
          createdAt: date,
          updatedAt: date,
        ),
        items: [
          BillItem(
            billId: 0,
            description: 'Work',
            quantity: 1,
            ratePaise: totalPaise,
            amountPaise: totalPaise,
          ),
        ],
      );
    }

    await addBill(aliceId, 'INV-OLD', lastMonth, 500000);
    await addBill(aliceId, 'INV-NEW', now, 300000);
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets('dashboard renders stats, charts and breakeven card', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardScreen(
            customerRepository: customerRepository,
            billRepository: billRepository,
            expenseRepository: expenseRepository,
            invoiceRepository: invoiceRepository,
          ),
        ),
      ),
    );

    await tester.runAsync(() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('Pending sync'), findsOneWidget);

    expect(find.text('Amount to breakeven'), findsOneWidget);
    expect(find.text('₹992000.00 remaining'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Earnings — this month vs last month'),
      200,
    );
    expect(find.text('Earnings — this month vs last month'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('New customers — this month vs last month'),
      200,
    );
    expect(
      find.text('New customers — this month vs last month'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(find.text('Net worth'), 200);
    expect(find.text('Net worth'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Recent transactions'), 200);
    expect(find.text('Recent transactions'), findsOneWidget);
    expect(find.text('INV-NEW'), findsOneWidget);
  });
}
