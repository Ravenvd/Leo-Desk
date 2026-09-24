import 'package:flutter/material.dart';

import '../models/price_calculation.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final _stitchesController = TextEditingController();
  final _rateController = TextEditingController();
  final _ebController = TextEditingController();
  final _rentController = TextEditingController();

  bool _isAari = false;
  bool _isOvernight = false;
  PriceCalculation? _calculation;

  static const _machineSpeed = 800.0;
  static const _timeSurchargePercent = 20.0;
  static const _aariSurchargePercent = 60.0;
  static const _ebAllocationPercent = 5.0;
  static const _rentAllocationPercent = 5.0;
  static const _overnightSurchargePercent = 25.0;
  static const _labourPercent = 20.0;

  @override
  void dispose() {
    _stitchesController.dispose();
    _rateController.dispose();
    _ebController.dispose();
    _rentController.dispose();
    super.dispose();
  }

  void _calculate() {
    final stitches = int.tryParse(_stitchesController.text.trim());
    final rate = double.tryParse(_rateController.text.trim());
    final eb = double.tryParse(_ebController.text.trim()) ?? 0;
    final rent = double.tryParse(_rentController.text.trim()) ?? 0;

    if (stitches == null || stitches <= 0 || rate == null || rate < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid stitch count and stitch rate.'),
        ),
      );
      return;
    }

    setState(() {
      _calculation = PriceCalculator.calculate(
        PriceCalculationInput(
          stitches: stitches,
          ratePerThousandStitches: rate,
          monthlyEbBill: eb,
          monthlyRent: rent,
          isAari: _isAari,
          isOvernight: _isOvernight,
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
      appBar: AppBar(title: const Text('Cost Calculator')),
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
              controller: _rateController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Rate per 1,000 stitches',
                prefixText: '₹ ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ebController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Monthly EB bill',
                prefixText: '₹ ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rentController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Monthly rent',
                prefixText: '₹ ',
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Aari work'),
              subtitle: const Text('+60% of stitch charge'),
              value: _isAari,
              onChanged: (value) => setState(() => _isAari = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Overnight work'),
              subtitle: const Text('+25% of work charge'),
              value: _isOvernight,
              onChanged: (value) => setState(() => _isOvernight = value),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _calculate,
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
              '800 stitches/min • +20% when estimated time exceeds 1 hour • '
              'EB 5% • Rent 5% • Labour 20% • Overnight 25% • '
              'final cost rounded to the nearest ₹50',
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
            Text(
              'Estimated machine time: \${_formatMinutes(calculation.estimatedMinutes)}',
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
          Text('₹\${value.toStringAsFixed(0)}', style: style),
        ],
      ),
    );
  }

  String _formatMinutes(double minutes) {
    if (minutes < 60) return '\${minutes.toStringAsFixed(1)} min';
    final hours = minutes ~/ 60;
    final remaining = (minutes - hours * 60).round();
    return '\${hours}h \${remaining}m';
  }
}
