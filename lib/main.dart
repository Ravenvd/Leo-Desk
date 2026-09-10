import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/database/app_database.dart';
import 'core/sync/sync_server.dart';
import 'features/customers/repositories/customer_repository.dart';
import 'features/customers/screens/customers_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await AppDatabase.database;

  if (Platform.isWindows){
    final syncServer = SyncServer();
    await syncServer.start();
  }

  runApp(const LeoDeskApp());
}

class LeoDeskApp extends StatelessWidget {
  const LeoDeskApp({super.key});

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
      home: const LeoDeskShell(),
    );
  }
}

class LeoDeskShell extends StatefulWidget {
  const LeoDeskShell({super.key});

  @override
  State<LeoDeskShell> createState() => _LeoDeskShellState();
}

class _LeoDeskShellState extends State<LeoDeskShell> {
  int _selectedIndex = 0;

  List<Widget> get _pages => [
  const _PlaceholderPage(
    icon: Icons.dashboard_rounded,
    title: 'Dashboard',
    subtitle: 'Your business at a glance.',
  ),
  CustomersScreen(
    repository: CustomerRepository(),
  ),
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
];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 800;

        if (isWide) {
          return _buildDesktopLayout();
        }

        return _buildMobileLayout();
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
          Expanded(
            child: _pages[_selectedIndex],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leo Desk'),
      ),
      drawer: _MobileNavigation(
        selectedIndex: _selectedIndex,
        onSelected: _selectPage,
      ),
      body: _pages[_selectedIndex],
    );
  }

  void _selectPage(int index) {
    setState(() {
      _selectedIndex = index;
    });

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
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
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
              ],
            ),
          ),
          const Divider(),
          _NavigationItem(
            icon: Icons.settings_rounded,
            label: 'Settings',
            selected: false,
            onTap: () {},
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
          padding: EdgeInsets.fromLTRB(28, 28, 28, 20),
          child: Text(
            'Leo Desk',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
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
          icon: Icon(Icons.request_quote_outlined),
          selectedIcon: Icon(Icons.request_quote_rounded),
          label: Text('Quotations'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.inventory_2_outlined),
          selectedIcon: Icon(Icons.inventory_2_rounded),
          label: Text('Inventory'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long_rounded),
          label: Text('Invoices'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.payments_outlined),
          selectedIcon: Icon(Icons.payments_rounded),
          label: Text('Payments'),
        ),
      ],
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
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 64,
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}