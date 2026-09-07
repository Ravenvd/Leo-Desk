import 'package:flutter/material.dart';

import '../models/customer.dart';
import '../repositories/customer_repository.dart';

class CustomerFormScreen extends StatefulWidget {
  const CustomerFormScreen({
    super.key,
    required this.repository,
    this.customer,
  });

  final CustomerRepository repository;
  final Customer? customer;

  bool get isEditing => customer != null;

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _whatsappController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _notesController;

  late String _customerType;
  late String _serviceRequired;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    final customer = widget.customer;

    _nameController = TextEditingController(
      text: customer?.name ?? '',
    );
    _phoneController = TextEditingController(
      text: customer?.phone ?? '',
    );
    _whatsappController = TextEditingController(
      text: customer?.whatsapp ?? '',
    );
    _emailController = TextEditingController(
      text: customer?.email ?? '',
    );
    _addressController = TextEditingController(
      text: customer?.address ?? '',
    );
    _notesController = TextEditingController(
      text: customer?.notes ?? '',
    );

    _customerType = customer?.customerType ?? 'personal';
    _serviceRequired = customer?.serviceRequired ?? 'embroidery';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _whatsappController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveCustomer() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSaving = true;
    });

    try {
      final now = DateTime.now();
      final existingCustomer = widget.customer;

      final customer = Customer(
        id: existingCustomer?.id,
        name: _nameController.text.trim(),
        phone: _nullableValue(_phoneController.text),
        whatsapp: _nullableValue(_whatsappController.text),
        email: _nullableValue(_emailController.text),
        address: _nullableValue(_addressController.text),
        notes: _nullableValue(_notesController.text),
        customerType: _customerType,
        serviceRequired: _serviceRequired,
        createdAt: existingCustomer?.createdAt ?? now,
        updatedAt: now,
      );

      if (widget.isEditing) {
        await widget.repository.update(customer);
      } else {
        await widget.repository.insert(customer);
      }

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditing
                ? 'Unable to update customer.'
                : 'Unable to add customer.',
          ),
        ),
      );
    }
  }

  String? _nullableValue(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter the customer name.';
    }

    return null;
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';

    if (email.isEmpty) {
      return null;
    }

    final emailRegex = RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    );

    if (!emailRegex.hasMatch(email)) {
      return 'Please enter a valid email address.';
    }

    return null;
  }

  String? _validatePhone(String? value) {
    final phone = value?.trim() ?? '';

    if (phone.isEmpty) {
      return null;
    }

    final digitsOnly = phone.replaceAll(RegExp(r'\D'), '');

    if (digitsOnly.length < 10) {
      return 'Please enter a valid phone number.';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isEditing ? 'Edit Customer' : 'Add Customer';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 800,
            ),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(32),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 32),
                  _buildBasicInformation(),
                  const SizedBox(height: 24),
                  _buildContactInformation(),
                  const SizedBox(height: 24),
                  _buildAdditionalInformation(),
                  const SizedBox(height: 32),
                  _buildActions(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.isEditing ? 'Edit customer' : 'New customer',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.isEditing
              ? 'Update the customer details below.'
              : 'Add a customer to your Leo Desk database.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }

  Widget _buildBasicInformation() {
    return _FormSection(
      title: 'Basic Information',
      icon: Icons.person_outline_rounded,
      child: Column(
        children: [
          TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            enabled: !_isSaving,
            validator: _validateName,
            decoration: const InputDecoration(
              labelText: 'Customer name *',
              hintText: 'Enter customer name',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 16),
          _buildDropdown(
            label: 'Customer type',
            value: _customerType,
            icon: Icons.badge_outlined,
            items: const [
              DropdownMenuItem(
                value: 'personal',
                child: Text('Personal'),
              ),
              DropdownMenuItem(
                value: 'business',
                child: Text('Business'),
              ),
            ],
            onChanged: _isSaving
                ? null
                : (value) {
                    if (value == null) return;

                    setState(() {
                      _customerType = value;
                    });
                  },
          ),
          const SizedBox(height: 16),
          _buildDropdown(
            label: 'Service required',
            value: _serviceRequired,
            icon: Icons.design_services_outlined,
            items: const [
              DropdownMenuItem(
                value: 'embroidery',
                child: Text('Embroidery'),
              ),
              DropdownMenuItem(
                value: 'stitching',
                child: Text('Stitching'),
              ),
            ],
            onChanged: _isSaving
                ? null
                : (value) {
                    if (value == null) return;

                    setState(() {
                      _serviceRequired = value;
                    });
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildContactInformation() {
    return _FormSection(
      title: 'Contact Information',
      icon: Icons.contact_phone_outlined,
      child: Column(
        children: [
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            enabled: !_isSaving,
            validator: _validatePhone,
            decoration: const InputDecoration(
              labelText: 'Phone',
              hintText: 'Enter phone number',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _whatsappController,
            keyboardType: TextInputType.phone,
            enabled: !_isSaving,
            validator: _validatePhone,
            decoration: const InputDecoration(
              labelText: 'WhatsApp',
              hintText: 'Enter WhatsApp number',
              prefixIcon: Icon(Icons.chat_outlined),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            enabled: !_isSaving,
            validator: _validateEmail,
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: 'Enter email address',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdditionalInformation() {
    return _FormSection(
      title: 'Additional Information',
      icon: Icons.notes_rounded,
      child: Column(
        children: [
          TextFormField(
            controller: _addressController,
            textCapitalization: TextCapitalization.sentences,
            enabled: !_isSaving,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Address',
              hintText: 'Enter customer address',
              prefixIcon: Icon(Icons.location_on_outlined),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _notesController,
            textCapitalization: TextCapitalization.sentences,
            enabled: !_isSaving,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Notes',
              hintText: 'Add any notes about this customer',
              prefixIcon: Icon(Icons.notes_outlined),
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required IconData icon,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?>? onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton(
          onPressed: _isSaving
              ? null
              : () {
                  Navigator.of(context).pop();
                },
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: _isSaving ? null : _saveCustomer,
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : Icon(
                  widget.isEditing
                      ? Icons.save_rounded
                      : Icons.person_add_rounded,
                ),
          label: Text(
            _isSaving
                ? 'Saving...'
                : widget.isEditing
                    ? 'Save Changes'
                    : 'Add Customer',
          ),
        ),
      ],
    );
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}