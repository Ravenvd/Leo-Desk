import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leo_desk/core/database/app_database.dart';
import 'package:leo_desk/core/sync/sync_client.dart';
import 'package:leo_desk/core/sync/sync_config.dart';
import 'package:leo_desk/core/sync/sync_manager.dart';
import 'package:leo_desk/core/sync/sync_server.dart';
import 'package:leo_desk/features/billing/repositories/bill_repository.dart';
import 'package:leo_desk/features/customers/repositories/customer_repository.dart';
import 'package:leo_desk/features/expenses/models/expense.dart';
import 'package:leo_desk/features/invoices/repositories/invoice_repository.dart';
import 'package:leo_desk/features/orders/repositories/order_repository.dart';
import 'package:leo_desk/features/expenses/repositories/expense_repository.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDirectory;
  late Database serverDatabase;
  late Database clientDatabase;
  late int port;

  setUp(() async {
    testDirectory =
        await Directory.systemTemp.createTemp('leo_desk_sync_offline_test_');

    serverDatabase = await AppDatabase.openTestDatabase(
      path: testDirectory.path + Platform.pathSeparator + 'server.db',
    );
    clientDatabase = await AppDatabase.openTestDatabase(
      path: testDirectory.path + Platform.pathSeparator + 'client.db',
    );

    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = socket.port;
    await socket.close();
  });

  tearDown(() async {
    await serverDatabase.close();
    await clientDatabase.close();
    await testDirectory.delete(recursive: true);
  });

  test(
    'keeps local expense pending while Windows is offline, then pushes it after recovery',
    () async {
      final clientExpenses = ExpenseRepository(database: clientDatabase);
      final serverExpenses = ExpenseRepository(database: serverDatabase);

      final expense = Expense(
        uuid: 'offline-recovery-expense',
        expenseDate: DateTime.utc(2026, 1, 10),
        category: 'Miscellaneous',
        description: 'Offline expense',
        amountPaise: 125000,
        notes: 'Created while Windows was unavailable',
        createdAt: DateTime.utc(2026, 1, 10, 8),
        updatedAt: DateTime.utc(2026, 1, 10, 8),
      );
      await clientExpenses.insert(expense);

      final manager = SyncManager(
        client: SyncClient(
          serverAddress: '127.0.0.1',
          port: port,
          token: SyncConfig.defaultToken,
        ),
        expenseRepository: clientExpenses,
        saveLastSyncTime: (_) async {},
      );

      final offlineResult = await manager.sync();

      expect(offlineResult.connected, isFalse);
      expect(
        (await clientExpenses.getPending()).map((item) => item.uuid),
        contains(expense.uuid),
      );
      expect(await serverExpenses.getById(1), isNull);

      final server = SyncServer(
        customerRepository: CustomerRepository(database: serverDatabase),
        billRepository: BillRepository(database: serverDatabase),
        expenseRepository: serverExpenses,
        invoiceRepository: InvoiceRepository(database: serverDatabase),
        orderRepository: OrderRepository(database: serverDatabase),
      );
      await server.start(port: port);

      try {
        final recoveredResult = await manager.sync();

        expect(recoveredResult.connected, isTrue);
        expect(recoveredResult.expensesPushed, 1);
        expect(await clientExpenses.getPending(), isEmpty);

        final serverExpense = await serverExpenses.getById(1);
        expect(serverExpense, isNotNull);
        expect(serverExpense!.uuid, expense.uuid);
        expect(serverExpense.description, expense.description);
        expect(serverExpense.amountPaise, expense.amountPaise);
      } finally {
        await server.stop();
      }
    },
  );
}
