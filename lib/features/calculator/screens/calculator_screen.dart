import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/price_calculation.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final _stitchesController = TextEditingController();
  final _piecesController = TextEditingController();
  final _timePerPieceController = TextEditingController();

  static const _machineSpeed = 800.0;
  static const _timeSurchargePercent = 20.0;
  static const _aariSurchargePercent = 60.0;
  static const _ebAllocationPercent = 5.0;
  static const _rentAllocationPercent = 5.0;
  static const _overnightSurchargePercent = 25.0;
  static const _labourPercent = 20.0;

  double _monthlyEbBill = 0;
  double _monthlyRent = 0;
  String? _savedMonthKey;
  bool _settingsLoaded = false;
  bool _isAari = false;
  DeliveryWindow _deliveryWindow = DeliveryWindow.under24Hours;
  PriceCalculation? _calculation;

  @override
  void initState() {
    super.initState();
    _stitchesController.addListener(_updateTimePerPiece);
    _loadMonthlySettings();
  }

  void _updateTimePerPiece() {
    final stitches = int.tryParse(_stitchesController.text.trim());
    if (stitches == null || stitches <= 0) {
      if (_timePerPieceController.text.isNotEmpty) {
        _timePerPieceController.clear();
      }
      return;
    }

    final minutesPerPiece = stitches / _machineSpeed;
    final value = minutesPerPiece.toStringAsFixed(1);

    if (_timePerPieceController.text != value) {
      _timePerPieceController.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  @override
  void dispose() {
    _stitchesController.removeListener(_updateTimePerPiece);
    _stitchesController.dispose();
    _piecesController.dispose();
    _timePerPieceController.dispose();
    super.dispose();
  }

  String _currentMonthKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  Future<void> _loadMonthlySettings() async {
    final prefs = await SharedPreferences.getInstance();
    final monthKey = _currentMonthKey();
    final savedMonth = prefs.getString('calculator_settings_month');

    if (!mounted) return;

    setState(() {
      _monthlyEbBill = prefs.getDouble('calculator_monthly_eb') ?? 0;
      _monthlyRent = prefs.getDouble('calculator_monthly_rent') ?? 0;
      _savedMonthKey = savedMonth;
      _settingsLoaded = true;
    });

    if (savedMonth != monthKey) {
      await _showMonthlySettingsDialog();
    }
  }

  Future<void> _showMonthlySettingsDialog() async {
    final ebController = TextEditingController(
      text: _monthlyEbBill == 0 ? '' : _monthlyEbBill.toStringAsFixed(0),
    );
    final rentController = TextEditingController(
      text: _monthlyRent == 0 ? '' : _monthlyRent.toStringAsFixed(0),
    );

    try {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Monthly cost setup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter this month’s EB bill and rent. These values will be '
                'saved and used for all calculations until next month.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ebController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Monthly EB bill',
                  prefixText: '₹ ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: rentController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Monthly rent',
                  prefixText: '₹ ',
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                final eb = double.tryParse(ebController.text.trim());
                final rent = double.tryParse(rentController.text.trim());

                if (eb == null || eb < 0 || rent == null || rent < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Enter valid EB and rent amounts.'),
                    ),
                  );
                  return;
                }

                final monthKey = _currentMonthKey();
                final prefs = await SharedPreferences.getInstance();

                await prefs.setDouble('calculator_monthly_eb', eb);
                await prefs.setDouble('calculator_monthly_rent', rent);
                await prefs.setString('calculator_settings_month', monthKey);

                if (!mounted) return;
                setState(() {
                  _monthlyEbBill = eb;
                  _monthlyRent = rent;
                  _savedMonthKey = monthKey;
                });
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Save for this month'),
            ),
          ],
        ),
      );
    } finally {
      ebController.dispose();
      rentController.dispose();
    }
  }

  void _calculate() {
    final stitches = int.tryParse(_stitchesController.text.trim());
    final pieces = int.tryParse(_piecesController.text.trim());
    final timePerPiece =
        double.tryParse(_timePerPieceController.text.trim());

    if (!_settingsLoaded || _savedMonthKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set this month’s EB bill and rent first.'),
        ),
      );
      return;
    }

    if (stitches == null ||
        stitches <= 0 ||
        pieces == null ||
        pieces <= 0 ||
        timePerPiece == null ||
        timePerPiece <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter valid stitches, pieces, and time per piece.'),
        ),
      );
      return;
    }

    setState(() {
      _calculation = PriceCalculator.calculate(
        PriceCalculationInput(
          stitches: stitches,
          pieces: pieces,
          timePerPieceMinutes: timePerPiece,
          monthlyEbBill: _monthlyEbBill,
          monthlyRent: _monthlyRent,
          deliveryWindow: _deliveryWindow,
          isAari: _isAari,
          machineSpeed: _machineSpeed,
          timeSurchargePercent: _timeSurchargePercent,
          aariSurchargePercent: _aariSurchargePercent,
          ebAllocationPercent: _ebAllocationPercent,
          rentAllocationPercent: _rentAllocationPercent,
          overnightSurchargePercent: _overnightSurchargePercent,
          labourPercent: _labourPercent,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cost Calculator'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final form = _buildForm();
          final result = _buildResult();

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: form),
                      const SizedBox(width: 20),
                      Expanded(child: result),
                    ],
                  )
                : Column(
                    children: [
                      form,
                      const SizedBox(height: 20),
                      result,
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _buildForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Work details', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _stitchesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Number of stitches',
                prefixIcon: Icon(Icons.grid_4x4_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _piecesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Number of pieces',
                prefixIcon: Icon(Icons.layers_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _timePerPieceController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Time per piece (minutes)',
                helperText: 'Calculated automatically at 800 stitches/min',
                prefixIcon: Icon(Icons.timer_outlined),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<DeliveryWindow>(
              initialValue: _deliveryWindow,
              decoration: const InputDecoration(
                labelText: 'Delivery date',
                prefixIcon: Icon(Icons.event_available_rounded),
              ),
              items: DeliveryWindow.values
                  .map(
                    (window) => DropdownMenuItem(
                      value: window,
                      child: Text(window.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _deliveryWindow = value);
                }
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Aari work'),
              subtitle: const Text('+60% of stitch charge'),
              value: _isAari,
              onChanged: (value) => setState(() => _isAari = value),
            ),
            const SizedBox(height: 8),
            if (_settingsLoaded)
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_rounded),
                  title: Text(
                    'This month: EB ₹${_monthlyEbBill.toStringAsFixed(0)} • '
                    'Rent ₹${_monthlyRent.toStringAsFixed(0)}',
                  ),
                  subtitle: const Text(
                    'Saved for the current month',
                  ),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _settingsLoaded ? _calculate : null,
              icon: const Icon(Icons.calculate_rounded),
              label: const Text('Calculate cost'),
            ),
            const SizedBox(height: 16),
            Text(
              'Fixed assumptions',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              '₹40 per 1,000 stitches • 800 stitches/min • +20% when total '
              'work time exceeds 1 hour • Aari +60% • EB 5% • Rent 5% • '
              'Labour 20% • Overnight +25% • final cost rounded to nearest ₹50',
            ),
            const SizedBox(height: 8),
            const Text(
              'Overnight is automatic when the required work exceeds 12 hours '
              'per day within the selected delivery window.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final calculation = _calculation;
    if (calculation == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text('Enter the work details to calculate the cost.'),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cost breakdown',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _row(
              'Theoretical machine time',
              calculation.estimatedMachineMinutes / 60,
              suffix: ' h',
            ),
            _row(
              'Maximum embroidery time',
              calculation.totalWorkMinutes / 60,
              suffix: ' h',
              emphasized: true,
            ),
            _row(
              'Required work per day',
              calculation.requiredHoursPerDay,
              suffix: ' h/day',
            ),
            const SizedBox(height: 4),
            Text(
              calculation.overnightRequired
                  ? 'Overnight work: YES (+25%)'
                  : 'Overnight work: NO',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(height: 28),
            _row('Stitch charge', calculation.stitchCharge),
            if (calculation.timeSurcharge > 0)
              _row('Time surcharge', calculation.timeSurcharge),
            if (calculation.aariSurcharge > 0)
              _row('Aari surcharge', calculation.aariSurcharge),
            _row('Work charge', calculation.workCharge, emphasized: true),
            const Divider(height: 28),
            _row('EB allocation (5%)', calculation.ebAllocation),
            _row('Rent allocation (5%)', calculation.rentAllocation),
            if (calculation.overnightSurcharge > 0)
              _row(
                'Overnight surcharge (25%)',
                calculation.overnightSurcharge,
              ),
            _row('Labour (20%)', calculation.labourCharge),
            const Divider(height: 28),
            _row('Calculated cost', calculation.totalBeforeRounding),
            _row(
              'FINAL COST',
              calculation.finalCost,
              emphasized: true,
              large: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    String label,
    double value, {
    String suffix = '',
    bool emphasized = false,
    bool large = false,
  }) {
    final style = large
        ? Theme.of(context).textTheme.headlineMedium
        : emphasized
            ? Theme.of(context).textTheme.titleMedium
            : Theme.of(context).textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(
            suffix.isEmpty
                ? '₹${value.toStringAsFixed(0)}'
                : '${value.toStringAsFixed(1)}$suffix',
            style: style,
          ),
        ],
      ),
    );
  }
}
