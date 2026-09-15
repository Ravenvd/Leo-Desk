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
import 'features/billing/repositories/bill_repository.dart';
import 'features/customers/repositories/customer_repository.dart';
import 'features/customers/screens/customers_screen.dart';
import 'features/dashboard/screens/dashboard_screen.dart';
import 'features/expenses/repositories/expense_repository.dart';
import 'features/expenses/screens/expenses_screen.dart';
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
    const Duration(minutes: 10),
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
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF7F8FC),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
      ),
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
        ),
        CustomersScreen(repository: CustomerRepository()),
        const _PlaceholderPage(
          icon: Icons.request_quote_rounded,
          title: 'Quotations',
          subtitle: 'Create and track quotations.',
        ),
        const _PlaceholderPage(
          icon: Icons.inventory_2_rounded,
          title: 'Inventory',
          subtitle: 'Track materials and stock.',
        ),
        const _PlaceholderPage(
          icon: Icons.receipt_long_rounded,
          title: 'Invoices',
          subtitle: 'Manage invoices and billing.',
        ),
        const _PlaceholderPage(
          icon: Icons.payments_rounded,
          title: 'Payments',
          subtitle: 'Track payments and labour expenses.',
        ),
        ExpensesScreen(repository: ExpenseRepository()),
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
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
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
            padding: EdgeInsets.fromLTRB(12, 12, 12, 32),
            child: Text(
              'Leo Desk',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
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
                  icon: Icons.request_quote_rounded,
                  label: 'Quotations',
                  selected: selectedIndex == 2,
                  onTap: () => onSelected(2),
                ),
                _NavigationItem(
                  icon: Icons.inventory_2_rounded,
                  label: 'Inventory',
                  selected: selectedIndex == 3,
                  onTap: () => onSelected(3),
                ),
                _NavigationItem(
                  icon: Icons.receipt_long_rounded,
                  label: 'Invoices',
                  selected: selectedIndex == 4,
                  onTap: () => onSelected(4),
                ),
                _NavigationItem(
                  icon: Icons.payments_rounded,
                  label: 'Payments',
                  selected: selectedIndex == 5,
                  onTap: () => onSelected(5),
                ),
                _NavigationItem(
                  icon: Icons.money_off_rounded,
                  label: 'Expenses',
                  selected: selectedIndex == 6,
                  onTap: () => onSelected(6),
                ),
              ],
            ),
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
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Leo Desk',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                ),
              ),
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
                    icon: Icons.request_quote_rounded,
                    label: 'Quotations',
                    selected: selectedIndex == 2,
                    onTap: () => onSelected(2),
                  ),
                  _NavigationItem(
                    icon: Icons.inventory_2_rounded,
                    label: 'Inventory',
                    selected: selectedIndex == 3,
                    onTap: () => onSelected(3),
                  ),
                  _NavigationItem(
                    icon: Icons.receipt_long_rounded,
                    label: 'Invoices',
                    selected: selectedIndex == 4,
                    onTap: () => onSelected(4),
                  ),
                  _NavigationItem(
                    icon: Icons.payments_rounded,
                    label: 'Payments',
                    selected: selectedIndex == 5,
                    onTap: () => onSelected(5),
                  ),
                  _NavigationItem(
                    icon: Icons.money_off_rounded,
                    label: 'Expenses',
                    selected: selectedIndex == 6,
                    onTap: () => onSelected(6),
                  ),
                ],
              ),
            ),
            _NavigationItem(
              icon: Icons.settings_rounded,
              label: 'Settings',
              selected: selectedIndex == 7,
              onTap: () => onSelected(7),
            ),
          ],
        ),
      ),
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
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: selected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: onTap,
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(subtitle),
        ],
      ),
    );
  }
}
