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
import 'package:leo_desk/features/expenses/repositories/expense_repository.dart';
import 'package:leo_desk/features/invoices/repositories/invoice_repository.dart';
import 'package:leo_desk/features/orders/repositories/order_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory testDirectory;
  late Database serverDatabase;
  late Database clientDatabase;
  late SyncServer server;

  setUp(() async {
    testDirectory =
        await Directory.systemTemp.createTemp('leo_desk_expense_tombstone_');

    serverDatabase = await AppDatabase.openTestDatabase(
      path: '${testDirectory.path}${Platform.pathSeparator}server.db',
    );
    clientDatabase = await AppDatabase.openTestDatabase(
      path: '${testDirectory.path}${Platform.pathSeparator}client.db',
    );

    server = SyncServer(
      customerRepository: CustomerRepository(database: serverDatabase),
      billRepository: BillRepository(database: serverDatabase),
      expenseRepository: ExpenseRepository(database: serverDatabase),
      invoiceRepository: InvoiceRepository(database: serverDatabase),
      orderRepository: OrderRepository(database: serverDatabase),
    );
    await server.start(port: 0);
  });

  tearDown(() async {
    await server.stop();
    await serverDatabase.close();
    await clientDatabase.close();
    await testDirectory.delete(recursive: true);
  });

  Expense makeExpense({
    required String uuid,
    String description = 'Embroidery thread',
    String syncStatus = Expense.syncStatusPending,
  }) {
    final now = DateTime.utc(2026, 1, 1);
    return Expense(
      uuid: uuid,
      syncStatus: syncStatus,
      expenseDate: now,
      category: 'Raw Materials',
      description: description,
      amountPaise: 12500,
      notes: 'Test expense',
      createdAt: now,
      updatedAt: now,
    );
  }

  SyncManager makeManager() {
    return SyncManager(
      client: SyncClient(
        serverAddress: '127.0.0.1',
        port: server.port!,
        token: SyncConfig.defaultToken,
      ),
      customerRepository: CustomerRepository(database: clientDatabase),
      billRepository: BillRepository(database: clientDatabase),
      expenseRepository: ExpenseRepository(database: clientDatabase),
      invoiceRepository: InvoiceRepository(database: clientDatabase),
      orderRepository: OrderRepository(database: clientDatabase),
      saveLastSyncTime: (_) async {},
    );
  }

  test('Android deletion propagates and both databases physically remove it',
      () async {
    final client = ExpenseRepository(database: clientDatabase);
    final serverRepo = ExpenseRepository(database: serverDatabase);

    await client.insert(makeExpense(uuid: 'android-delete'));

    await makeManager().sync();

    final local = (await client.getAll()).single;
    await client.delete(local.id!);

    expect(await client.getAll(), isEmpty);
    expect((await client.getPending()).single.syncStatus,
        Expense.syncStatusDeletedPending);

    final result = await makeManager().sync();

    expect(result.expensesPushed, 1);
    expect(result.expensesPulled, 1);
    expect(await client.getAll(), isEmpty);
    expect(await client.getPending(), isEmpty);
    expect(await serverRepo.getAll(), isEmpty);
    expect(await serverRepo.getAllForSync(), isEmpty);
  });

  test('Windows deletion propagates to Android and is then physically removed',
      () async {
    final client = ExpenseRepository(database: clientDatabase);
    final serverRepo = ExpenseRepository(database: serverDatabase);

    await serverRepo.insert(
      makeExpense(
        uuid: 'windows-delete',
        syncStatus: Expense.syncStatusSynced,
      ),
    );
    await serverRepo.markSynced('windows-delete');

    await makeManager().sync();

    final serverExpense = (await serverRepo.getAll()).single;
    await serverRepo.delete(serverExpense.id!);

    expect(await serverRepo.getAll(), isEmpty);
    expect((await serverRepo.getAllForSync()).single.syncStatus,
        Expense.syncStatusDeletedPending);

    final result = await makeManager().sync();

    expect(result.expensesPulled, 1);
    expect(await client.getAll(), isEmpty);
    expect(await serverRepo.getAll(), isEmpty);
    expect(await serverRepo.getAllForSync(), isEmpty);
  });

  test('a stale Android update cannot resurrect a Windows-deleted expense',
      () async {
    final client = ExpenseRepository(database: clientDatabase);
    final serverRepo = ExpenseRepository(database: serverDatabase);

    await serverRepo.insert(
      makeExpense(
        uuid: 'no-resurrection',
        syncStatus: Expense.syncStatusSynced,
      ),
    );
    await serverRepo.markSynced('no-resurrection');

    await makeManager().sync();

    final local = (await client.getAll()).single;
    await serverRepo.delete((await serverRepo.getAll()).single.id!);
    await client.update(
      local.copyWith(description: 'Stale Android edit'),
    );

    final result = await makeManager().sync();

    expect(result.expensesPushed, 0);
    expect(result.expensesPulled, 1);
    expect(await client.getAll(), isEmpty);
    expect(await serverRepo.getAll(), isEmpty);
    expect(await serverRepo.getAllForSync(), isEmpty);
  });
}
