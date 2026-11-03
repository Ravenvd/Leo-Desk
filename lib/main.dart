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
import 'features/lock_screen/startup_lock_screen.dart';
import 'features/lock_screen/inactivity_lock.dart';
import 'features/inventory/repositories/asset_repository.dart';
import 'features/inventory/repositories/consumable_repository.dart';
import 'features/inventory/screens/inventory_screen.dart';
import 'features/orders/screens/orders_screen.dart';
import 'features/sync/screens/sync_settings_screen.dart';
import 'features/staff/repositories/staff_repository.dart';
import 'features/staff/screens/staff_manager_screen.dart';

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
  bool _isLocked = Platform.isWindows;

  List<Widget> get _pages => [
        DashboardScreen(
          customerRepository: CustomerRepository(),
          billRepository: BillRepository(),
          expenseRepository: ExpenseRepository(),
          invoiceRepository: InvoiceRepository(),
        ),
        CustomersScreen(repository: CustomerRepository()),
        OrdersScreen(),
        BillsScreen(),
        InvoicesScreen(),
        ExpensesScreen(repository: ExpenseRepository()),
        InventoryScreen(
          assetRepository: AssetRepository(),
          consumableRepository: ConsumableRepository(),
        ),
        const CalculatorScreen(),
        const _ComingSoonScreen(
          title: 'Stitch Estimator',
          description: 'Artwork-based stitch and thread estimation will be available here.',
          icon: Icons.auto_awesome_rounded,
        ),
        StaffManagerScreen(repository: StaffRepository()),
        SyncSettingsScreen(syncServer: widget.syncServer),
      ];

  @override
  Widget build(BuildContext context) {
    return InactivityLock(
      enabled: Platform.isWindows && !_isLocked,
      onTimeout: () => setState(() => _isLocked = true),
      child: Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return constraints.maxWidth >= 800
                  ? _buildDesktopLayout()
                  : _buildMobileLayout();
            },
          ),
          if (_isLocked)
            StartupLockScreen(
              onUnlock: () => setState(() => _isLocked = false),
            ),
        ],
      ),
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
        onSelected: (index) {
          Navigator.of(context).pop();
          _selectPage(index);
        },
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
      width: 270,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 28),
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
                const SizedBox(height: 12),
                _NavigationGroup(
                  icon: Icons.business_rounded,
                  title: 'Business Management',
                  selected: selectedIndex >= 1 && selectedIndex <= 5,
                  children: [
                    _GroupDestination(icon: Icons.people_alt_rounded, label: 'Customers', selected: selectedIndex == 1, onTap: () => onSelected(1)),
                    _GroupDestination(icon: Icons.shopping_bag_rounded, label: 'Orders', selected: selectedIndex == 2, onTap: () => onSelected(2)),
                    _GroupDestination(icon: Icons.payments_rounded, label: 'Bills', selected: selectedIndex == 3, onTap: () => onSelected(3)),
                    _GroupDestination(icon: Icons.receipt_long_rounded, label: 'Invoices', selected: selectedIndex == 4, onTap: () => onSelected(4)),
                    _GroupDestination(icon: Icons.money_off_rounded, label: 'Expenses', selected: selectedIndex == 5, onTap: () => onSelected(5)),
                  ],
                ),
                _NavigationGroup(
                  icon: Icons.factory_rounded,
                  title: 'Production Management',
                  selected: selectedIndex >= 6 && selectedIndex <= 9,
                  children: [
                    _GroupDestination(icon: Icons.inventory_2_rounded, label: 'Inventory', selected: selectedIndex == 6, onTap: () => onSelected(6)),
                    _GroupDestination(icon: Icons.calculate_rounded, label: 'Pricing Calculator', selected: selectedIndex == 7, onTap: () => onSelected(7)),
                    _GroupDestination(icon: Icons.auto_awesome_rounded, label: 'Stitch Estimator', selected: selectedIndex == 8, onTap: () => onSelected(8)),
                    _GroupDestination(icon: Icons.people_alt_rounded, label: 'Staff', selected: selectedIndex == 9, onTap: () => onSelected(9)),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          _NavigationItem(
            icon: Icons.settings_rounded,
            label: 'Settings',
            selected: selectedIndex == 10,
            onTap: () => onSelected(10),
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 28),
              child: _LeoLogo(width: 145),
            ),
            _NavigationItem(
              icon: Icons.dashboard_rounded,
              label: 'Dashboard',
              selected: selectedIndex == 0,
              onTap: () => onSelected(0),
            ),
            const SizedBox(height: 12),
            _NavigationGroup(
              icon: Icons.business_rounded,
              title: 'Business Management',
              selected: selectedIndex >= 1 && selectedIndex <= 5,
              children: [
                _GroupDestination(icon: Icons.people_alt_rounded, label: 'Customers', selected: selectedIndex == 1, onTap: () => onSelected(1)),
                _GroupDestination(icon: Icons.shopping_bag_rounded, label: 'Orders', selected: selectedIndex == 2, onTap: () => onSelected(2)),
                _GroupDestination(icon: Icons.payments_rounded, label: 'Bills', selected: selectedIndex == 3, onTap: () => onSelected(3)),
                _GroupDestination(icon: Icons.receipt_long_rounded, label: 'Invoices', selected: selectedIndex == 4, onTap: () => onSelected(4)),
                _GroupDestination(icon: Icons.money_off_rounded, label: 'Expenses', selected: selectedIndex == 5, onTap: () => onSelected(5)),
              ],
            ),
            _NavigationGroup(
              icon: Icons.factory_rounded,
              title: 'Production Management',
              selected: selectedIndex >= 6 && selectedIndex <= 9,
              children: [
                _GroupDestination(icon: Icons.inventory_2_rounded, label: 'Inventory', selected: selectedIndex == 6, onTap: () => onSelected(6)),
                _GroupDestination(icon: Icons.calculate_rounded, label: 'Pricing Calculator', selected: selectedIndex == 7, onTap: () => onSelected(7)),
                _GroupDestination(icon: Icons.auto_awesome_rounded, label: 'Stitch Estimator', selected: selectedIndex == 8, onTap: () => onSelected(8)),
                _GroupDestination(icon: Icons.people_alt_rounded, label: 'Staff', selected: selectedIndex == 9, onTap: () => onSelected(9)),
              ],
            ),
            const Divider(height: 32),
            _NavigationItem(
              icon: Icons.settings_rounded,
              label: 'Settings',
              selected: selectedIndex == 10,
              onTap: () => onSelected(10),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationGroup extends StatelessWidget {
  const _NavigationGroup({
    required this.icon,
    required this.title,
    required this.selected,
    required this.children,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: selected,
        leading: Icon(icon, color: selected ? colors.primary : null),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? colors.primary : null,
          ),
        ),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.only(left: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        children: children,
      ),
    );
  }
}

class _GroupDestination extends StatelessWidget {
  const _GroupDestination({
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
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selected: selected,
        leading: Icon(icon, size: 20),
        title: Text(label),
        onTap: onTap,
      ),
    );
  }
}

class _ComingSoonScreen extends StatelessWidget {
  const _ComingSoonScreen({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52, color: colors.primary),
              const SizedBox(height: 20),
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(description, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Chip(label: const Text('Coming soon')),
            ],
          ),
        ),
      ),
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
