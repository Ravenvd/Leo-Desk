import 'package:flutter/material.dart';

import '../models/customer.dart';
import '../repositories/customer_repository.dart';
import 'customer_form_screen.dart';

class CustomerDetailsScreen extends StatefulWidget {
  const CustomerDetailsScreen({
    super.key,
    required this.repository,
    required this.customer,
  });

  final CustomerRepository repository;
  final Customer customer;

  @override
  State<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen> {
  late Customer _customer;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
  }

  Future<void> _editCustomer() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(
          repository: widget.repository,
          customer: _customer,
        ),
      ),
    );

    if (!mounted || result != true || _customer.id == null) return;

    try {
      final updated = await widget.repository.getById(_customer.id!);

      if (!mounted) return;

      if (updated != null) {
        setState(() {
          _customer = updated;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Reload customer error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  String _customerTypeLabel(String value) {
    switch (value) {
      case 'business':
        return 'Business';
      default:
        return 'Personal';
    }
  }

  String _serviceLabel(String value) {
    switch (value) {
      case 'stitching':
        return 'Stitching';
      default:
        return 'Embroidery';
    }
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Details'),
        actions: [
          IconButton(
            onPressed: _editCustomer,
            tooltip: 'Edit customer',
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ListView(
              padding: const EdgeInsets.all(32),
              children: [
                _buildProfileHeader(),
                const SizedBox(height: 24),
                _buildInformationCard(),
                const SizedBox(height: 24),
                _buildHistorySection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    final initial = _customer.name.isEmpty
        ? '?'
        : _customer.name.substring(0, 1).toUpperCase();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Row(
          children: [
            CircleAvatar(
              radius: 34,
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _customer.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        avatar: const Icon(Icons.badge_outlined, size: 18),
                        label: Text(
                          _customerTypeLabel(_customer.customerType),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      Chip(
                        avatar: const Icon(
                          Icons.design_services_outlined,
                          size: 18,
                        ),
                        label: Text(
                          _serviceLabel(_customer.serviceRequired),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInformationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Customer Information',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 20),
            _InfoRow(
              icon: Icons.phone_outlined,
              label: 'Phone',
              value: _customer.phone ?? 'Not provided',
            ),
            _InfoRow(
              icon: Icons.chat_outlined,
              label: 'WhatsApp',
              value: _customer.whatsapp ?? 'Not provided',
            ),
            _InfoRow(
              icon: Icons.email_outlined,
              label: 'Email',
              value: _customer.email ?? 'Not provided',
            ),
            _InfoRow(
              icon: Icons.location_on_outlined,
              label: 'Address',
              value: _customer.address ?? 'Not provided',
            ),
            _InfoRow(
              icon: Icons.notes_outlined,
              label: 'Notes',
              value: _customer.notes ?? 'No notes',
            ),
            const Divider(height: 28),
            _InfoRow(
              icon: Icons.calendar_today_outlined,
              label: 'Customer since',
              value: _formatDate(_customer.createdAt),
            ),
            _InfoRow(
              icon: Icons.update_outlined,
              label: 'Last updated',
              value: _formatDate(_customer.updatedAt),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history_rounded),
                const SizedBox(width: 12),
                Text(
                  'Customer History',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.timeline_rounded,
                    size: 44,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'History will appear here',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'This section is ready for quotations, orders, invoices, '
                    'payments, and other customer activity as those modules '
                    'are added.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Icon(icon, size: 20),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}
