import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/database/app_database.dart';
import 'core/sync/sync_config.dart';
import 'core/sync/sync_events.dart';
import 'core/sync/sync_manager.dart';
import 'core/sync/sync_server.dart';
import 'core/theme/app_theme.dart';
import 'features/billing/repositories/bill_repository.dart';
import 'features/calculator/screens/calculator_screen.dart';
import 'features/billing/screens/bills_screen.dart';
import 'features/customers/repositories/customer_repository.dart';
import 'features/customers/screens/customers_screen.dart';
import 'features/dashboard/screens/dashboard_screen.dart';
import 'features/expenses/repositories/expense_repository.dart';
import 'features/expenses/screens/expenses_screen.dart';
import 'features/invoices/repositories/invoice_repository.dart';
import 'features/invoices/screens/invoices_screen.dart';
import 'features/orders/screens/orders_screen.dart';
import 'features/sync/screens/sync_settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await AppDatabase.database;

  SyncServer? syncServer;
  if (Platform.isWindows) {
    syncServer = SyncServer();
    try {
      final config = await SyncConfig.load();
      await syncServer.start(port: config.serverPort);
    } catch (error) {
      debugPrint('Sync server failed to start: $error');
      syncServer = null;
    }
  }

  if (Platform.isAndroid) {
    _startAutoSync();
  }

  runApp(LeoDeskApp(syncServer: syncServer));
}

void _startAutoSync() {
  var syncInProgress = false;

  Future<void> runSync() async {
    if (syncInProgress) return;
    syncInProgress = true;

    try {
      final config = await SyncConfig.load();
      if (config.isConfigured) {
        final result = await SyncManager.fromConfig(config).sync();
        if (result.connected) {
          notifySyncCompleted();
        }
      }
    } catch (error) {
      debugPrint('Auto-sync failed: $error');
    } finally {
      syncInProgress = false;
    }
  }

  unawaited(runSync());

  Connectivity().onConnectivityChanged.listen((results) {
    if (results.contains(ConnectivityResult.wifi)) {
      unawaited(runSync());
    }
  });

  Timer.periodic(
    const Duration(minutes: 1),
    (_) => unawaited(runSync()),
  );
}

class LeoDeskApp extends StatelessWidget {
  const LeoDeskApp({super.key, this.syncServer});

  final SyncServer? syncServer;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Leo Desk',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: LeoDeskShell(syncServer: syncServer),
    );
  }
}

class LeoDeskShell extends StatefulWidget {
  const LeoDeskShell({super.key, this.syncServer});

  final SyncServer? syncServer;

  @override
  State<LeoDeskShell> createState() => _LeoDeskShellState();
}

class _LeoDeskShellState extends State<LeoDeskShell> {
  int _selectedIndex = 0;

  List<Widget> get _pages => [
        DashboardScreen(
          customerRepository: CustomerRepository(),
          billRepository: BillRepository(),
          expenseRepository: ExpenseRepository(),
          invoiceRepository: InvoiceRepository(),
        ),
        CustomersScreen(repository: CustomerRepository()),
        OrdersScreen(),
        InvoicesScreen(),
        BillsScreen(),
        ExpensesScreen(repository: ExpenseRepository()),
        const CalculatorScreen(),
        SyncSettingsScreen(syncServer: widget.syncServer),
      ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return constraints.maxWidth >= 800
            ? _buildDesktopLayout()
            : _buildMobileLayout();
      },
    );
  }

  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Row(
        children: [
          _DesktopNavigation(
            selectedIndex: _selectedIndex,
            onSelected: _selectPage,
          ),
          Expanded(child: _pages[_selectedIndex]),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Scaffold(
      appBar: AppBar(title: const Text('Leo Desk')),
      drawer: _MobileNavigation(
        selectedIndex: _selectedIndex,
        onSelected: _selectPage,
      ),
      body: _pages[_selectedIndex],
    );
  }

  void _selectPage(int index) {
    setState(() => _selectedIndex = index);
  }
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 24),
            child: _LeoLogo(width: 150),
          ),
          Expanded(
            child: ListView(
              children: [
                _NavigationItem(
                  icon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  selected: selectedIndex == 0,
                  onTap: () => onSelected(0),
                ),
                _NavigationItem(
                  icon: Icons.people_alt_rounded,
                  label: 'Customers',
                  selected: selectedIndex == 1,
                  onTap: () => onSelected(1),
                ),
                _NavigationItem(
                  icon: Icons.shopping_bag_rounded,
                  label: 'Orders',
                  selected: selectedIndex == 2,
                  onTap: () => onSelected(2),
                ),
                _NavigationItem(
                  icon: Icons.receipt_long_rounded,
                  label: 'Invoices',
                  selected: selectedIndex == 3,
                  onTap: () => onSelected(3),
                ),
                _NavigationItem(
                  icon: Icons.payments_rounded,
                  label: 'Bills',
                  selected: selectedIndex == 4,
                  onTap: () => onSelected(4),
                ),
                _NavigationItem(
                  icon: Icons.money_off_rounded,
                  label: 'Expenses',
                  selected: selectedIndex == 5,
                  onTap: () => onSelected(5),
                ),
              ],
            ),
          ),
          const Divider(),
          _NavigationItem(
            icon: Icons.calculate_rounded,
            label: 'Calculator',
            selected: selectedIndex == 6,
            onTap: () => onSelected(6),
          ),
          _NavigationItem(
            icon: Icons.settings_rounded,
            label: 'Settings',
            selected: selectedIndex == 7,
            onTap: () => onSelected(7),
          ),
        ],
      ),
    );
  }
}

class _MobileNavigation extends StatelessWidget {
  const _MobileNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationDrawer(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      children: const [
        Padding(
          padding: EdgeInsets.fromLTRB(28, 24, 28, 16),
          child: _LeoLogo(width: 140),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard_rounded),
          label: Text('Dashboard'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.people_alt_outlined),
          selectedIcon: Icon(Icons.people_alt_rounded),
          label: Text('Customers'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.shopping_bag_outlined),
          selectedIcon: Icon(Icons.shopping_bag_rounded),
          label: Text('Orders'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long_rounded),
          label: Text('Invoices'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.payments_outlined),
          selectedIcon: Icon(Icons.payments_rounded),
          label: Text('Bills'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.money_off_outlined),
          selectedIcon: Icon(Icons.money_off_rounded),
          label: Text('Expenses'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.calculate_outlined),
          selectedIcon: Icon(Icons.calculate_rounded),
          label: Text('Calculator'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings_rounded),
          label: Text('Settings'),
        ),
      ],
    );
  }
}

class _LeoLogo extends StatelessWidget {
  const _LeoLogo({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/leo_logo.png',
      width: width,
      fit: BoxFit.contain,
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        selected: selected,
        leading: Icon(icon),
        title: Text(label),
        onTap: onTap,
      ),
    );
  }
}
