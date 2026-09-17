import 'package:flutter/material.dart';

import '../models/expense.dart';
import '../repositories/expense_repository.dart';

class ExpenseDetailsScreen extends StatefulWidget {
  const ExpenseDetailsScreen({
    super.key,
    required this.repository,
    required this.expense,
  });

  final ExpenseRepository repository;
  final Expense expense;

  @override
  State<ExpenseDetailsScreen> createState() => _ExpenseDetailsScreenState();
}

class _ExpenseDetailsScreenState extends State<ExpenseDetailsScreen> {
  late Expense _expense;

  @override
  void initState() {
    super.initState();
    _expense = widget.expense;
  }

  Future<void> _deleteExpense() async {
    if (_expense.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text('Delete "${_expense.description}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await widget.repository.delete(_expense.id!);
    if (mounted) Navigator.pop(context, true);
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  String _formatDateTime(DateTime date) {
    final local = date.toLocal();
    return '${_formatDate(local)} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _formatMoney(int paise) => '₹${(paise / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Details'),
        actions: [
          IconButton(
            onPressed: _deleteExpense,
            tooltip: 'Delete expense',
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(32),
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildInformationCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 34,
              child: Icon(Icons.receipt_long_rounded, size: 32),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _expense.description,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Chip(
                    avatar: const Icon(Icons.category_outlined, size: 18),
                    label: Text(_expense.category),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatMoney(_expense.amountPaise),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
              'Expense Information',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            _InfoRow(
              icon: Icons.calendar_today_outlined,
              label: 'Expense date',
              value: _formatDate(_expense.expenseDate),
            ),
            _InfoRow(
              icon: Icons.category_outlined,
              label: 'Category',
              value: _expense.category,
            ),
            _InfoRow(
              icon: Icons.payments_outlined,
              label: 'Amount',
              value: _formatMoney(_expense.amountPaise),
            ),
            _InfoRow(
              icon: Icons.notes_outlined,
              label: 'Notes',
              value: _expense.notes?.isNotEmpty == true ? _expense.notes! : 'No notes',
            ),
            const Divider(height: 28),
            _InfoRow(
              icon: Icons.sync_outlined,
              label: 'Sync status',
              value: _expense.syncStatus,
            ),
            _InfoRow(
              icon: Icons.fingerprint_outlined,
              label: 'UUID',
              value: _expense.uuid,
            ),
            _InfoRow(
              icon: Icons.add_circle_outline,
              label: 'Created',
              value: _formatDateTime(_expense.createdAt),
            ),
            _InfoRow(
              icon: Icons.update_outlined,
              label: 'Last updated',
              value: _formatDateTime(_expense.updatedAt),
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
          SizedBox(width: 32, child: Icon(icon, size: 20)),
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
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
