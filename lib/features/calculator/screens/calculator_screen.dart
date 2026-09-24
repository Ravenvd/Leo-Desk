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
  final _monthlyEbController = TextEditingController();
  final _monthlyRentController = TextEditingController(text: '4500');
  final _timePerPieceController = TextEditingController();
  final _effectivePriceController = TextEditingController();


  bool _isAari = false;
  double _monthlyEbBill = 1000;
  double _monthlyRent = 4500;
  DeliveryWindow _deliveryWindow = DeliveryWindow.under24Hours;
  PriceCalculation? _calculation;
  double? _revenueRateDeficiencyPercent;

  @override
  void initState() {
    super.initState();
    _stitchesController.addListener(_updateTimePerPiece);
    _loadMonthlyCosts();
  }

  Future<void> _loadMonthlyCosts() async {
    final prefs = await SharedPreferences.getInstance();
    final eb = prefs.getDouble('calculator_monthly_eb_bill') ?? 1000;
    final rent = prefs.getDouble('calculator_monthly_rent') ?? 4500;
    if (!mounted) return;
    setState(() {
      _monthlyEbBill = eb;
      _monthlyRent = rent;
      _monthlyEbController.text = eb.toStringAsFixed(0);
      _monthlyRentController.text = rent.toStringAsFixed(0);
    });
  }

  Future<void> _saveMonthlyCosts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('calculator_monthly_eb_bill', _monthlyEbBill);
    await prefs.setDouble('calculator_monthly_rent', _monthlyRent);
  }

  void _updateTimePerPiece() {
    final stitches = int.tryParse(_stitchesController.text.trim());
    if (stitches == null || stitches <= 0) {
      if (_timePerPieceController.text.isNotEmpty) {
        _timePerPieceController.clear();
      }
      return;
    }

    final speed = _isAari ? PriceCalculator.aariEffectiveSpm : PriceCalculator.normalEffectiveSpm;
    final minutesPerPiece = stitches / speed;
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
    _monthlyEbController.dispose();
    _monthlyRentController.dispose();
    _timePerPieceController.dispose();
    _effectivePriceController.dispose();
    super.dispose();
  }

  void _calculate() {
    final stitches = int.tryParse(_stitchesController.text.trim());
    final pieces = int.tryParse(_piecesController.text.trim());
    if (stitches == null || stitches <= 0 || pieces == null || pieces <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter valid stitches and number of pieces.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _calculation = PriceCalculator.calculate(
        PriceCalculationInput(
          stitches: stitches,
          pieces: pieces,
          monthlyEbBill: _monthlyEbBill,
          monthlyRent: _monthlyRent,
          deliveryWindow: _deliveryWindow,
          isAari: _isAari,
        ),
      );
      _revenueRateDeficiencyPercent = null;
      _effectivePriceController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pricing Calculator'),
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
                      Expanded(child: Column(children: [result, if (_calculation != null) ...[
                        const SizedBox(height: 20),
                        _buildRevenueRateChecker(),
                      ]])),
                    ],
                  )
                : Column(
                    children: [
                      form,
                      const SizedBox(height: 20),
                      result,
                      if (_calculation != null) ...[
                        const SizedBox(height: 20),
                        _buildRevenueRateChecker(),
                      ],
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
            Text(
              'Order details',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _stitchesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Stitches per piece',
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
              controller: _monthlyEbController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Monthly EB bill',
                prefixText: '₹ ',
                prefixIcon: Icon(Icons.bolt_rounded),
              ),
              onChanged: (value) {
                _monthlyEbBill = double.tryParse(value) ?? 0;
                _saveMonthlyCosts();
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _monthlyRentController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Monthly rent',
                prefixText: '₹ ',
                prefixIcon: Icon(Icons.home_work_outlined),
              ),
              onChanged: (value) {
                _monthlyRent = double.tryParse(value) ?? 0;
                _saveMonthlyCosts();
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _timePerPieceController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Machine time per piece (minutes)',
                helperText: 'Calculated at 550 SPM normal / 300 SPM Aari',
                prefixIcon: Icon(Icons.timer_outlined),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<DeliveryWindow>(
              initialValue: _deliveryWindow,
              decoration: const InputDecoration(
                labelText: 'Delivery window',
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
              subtitle: const Text('300 SPM + 60% Aari surcharge'),
              value: _isAari,
              onChanged: (value) {
                setState(() => _isAari = value);
                _updateTimePerPiece();
              },
            ),
            const SizedBox(height: 8),
            const Text(
              'Bulk discount: 5–9 pieces 2% • 10–19 pieces 5% • '
              '20–29 pieces 7% • 30–39 pieces 9% • 40+ pieces 10%',
            ),
            const SizedBox(height: 8),
            const Text(
              'Designer fee is charged once per order based on stitches: '
              '<10,000 = ₹100 • 10,000–19,999 = ₹200 • '
              '20,000–29,999 = ₹300 • 30,000–39,999 = ₹400 • '
              '40,000+ = ₹500.',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _calculate,
              icon: const Icon(Icons.calculate_rounded),
              label: const Text('Calculate price'),
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
            child: Text('Enter the order details to calculate the price.'),
          ),
        ),
      );
    }

    final effectivePerPiece =
        calculation.totalOrderPrice / calculation.pieces;

    final discountLabel =
        'Bulk discount (' +
        calculation.discountPercent.toStringAsFixed(0) +
        '%)';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Price breakdown',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _row(
              'Machine time per piece',
              calculation.estimatedMachineMinutesPerPiece,
              suffix: ' min',
            ),
            _row(
              'Total machine time',
              calculation.totalMachineMinutes / 60,
              suffix: ' h',
            ),
            _row(
              'Required work per day',
              calculation.requiredHoursPerDay,
              suffix: ' h/day',
            ),
            if (calculation.overnightRequired)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Over 12 h/day at this delivery window',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            const Divider(height: 28),
            _row(
              'Production cost',
              calculation.productionCostPerHour,
              suffix: ' /h',
            ),
            _row(
              'Selling rate (+15% profit)',
              calculation.sellingRatePerHour,
              suffix: ' /h',
            ),
            _row(
              'Base production price',
              calculation.baseProductionPricePerPiece,
            ),
            if (calculation.aariAdjustment > 0)
              _row(
                'Aari adjustment (+60%)',
                calculation.aariAdjustment,
              ),
            _row(
              discountLabel,
              -calculation.discountPerPiece,
            ),
            _row(
              'Production price after discount',
              calculation.discountedProductionPricePerPiece,
            ),
            _row(
              'Final price per piece',
              calculation.finalPricePerPiece,
              emphasized: true,
            ),
            _row('Embroidery total', calculation.embroideryTotal),
            const Divider(height: 28),
            _row(
              'Designer fee (one time)',
              calculation.designerFee,
            ),
            const Divider(height: 28),
            _row(
              'TOTAL ORDER PRICE',
              calculation.totalOrderPrice,
              emphasized: true,
              large: true,
            ),
            const SizedBox(height: 8),
            Text(
              'Effective price per piece: ₹' +
                  effectivePerPiece.toStringAsFixed(2),
            ),
            const Divider(height: 32),
            Text(
              'Business target',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _row(
              'Operating capacity',
              calculation.monthlyOperatingHours,
              suffix: ' h/month',
            ),
            _row(
              'Monthly operating cost',
              calculation.monthlyOperatingCost,
            ),
            _row(
              'Monthly revenue target',
              calculation.monthlyRevenueTarget,
              emphasized: true,
            ),
            _row(
              'Target revenue rate',
              calculation.targetRevenuePerHour,
              suffix: ' /h',
              emphasized: true,
            ),
            const SizedBox(height: 8),
            Text(
              'Target includes 12-month recovery of the ₹10 lakh business loan, '
              '8% annual interest, wages, rent, EB, a 15% overhead & consumables buffer '
              'and 15% profit markup. '
              'It is shown here as a business target and is not added again '
              'to this order.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueRateChecker() {
    final calculation = _calculation!;
    final deficiency = _revenueRateDeficiencyPercent;
    final aboveTarget = deficiency != null && deficiency < 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Revenue rate checker',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Enter the effective price per piece you have decided to charge. '
              'The price is converted to an hourly revenue rate using the '
              'calculated machine time and compared with the target revenue rate.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _effectivePriceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Effective price per piece',
                prefixText: '₹ ',
                prefixIcon: Icon(Icons.sell_outlined),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                final price = double.tryParse(_effectivePriceController.text.trim());
                if (price == null || price < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter a valid effective price per piece.')),
                  );
                  return;
                }
                final realizedRevenueRate =
                    price / (calculation.estimatedMachineMinutesPerPiece / 60);
                setState(() {
                  _revenueRateDeficiencyPercent =
                      (calculation.targetRevenuePerHour - realizedRevenueRate) /
                          calculation.targetRevenuePerHour *
                          100;
                });
              },
              icon: const Icon(Icons.compare_arrows_rounded),
              label: const Text('Check revenue rate'),
            ),
            if (deficiency != null) ...[
              const Divider(height: 28),
              _row(
                'Your revenue rate',
                double.parse(_effectivePriceController.text.trim()) /
                    (calculation.estimatedMachineMinutesPerPiece / 60),
                suffix: ' /h',
              ),
              _row(
                'Target revenue rate',
                calculation.targetRevenuePerHour,
                suffix: ' /h',
              ),
              _row(
                aboveTarget ? 'Above target' : 'Revenue rate deficiency',
                deficiency.abs(),
                suffix: '%',
                emphasized: true,
              ),
              const SizedBox(height: 6),
              Text(
                aboveTarget
                    ? 'The chosen price produces a revenue rate ' + deficiency.abs().toStringAsFixed(1) + '% above the target.'
                    : deficiency == 0
                        ? 'The chosen price exactly matches the target revenue rate.'
                        : 'The chosen price produces a revenue rate ' + deficiency.toStringAsFixed(1) + '% below the target.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
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

    final formatted = suffix.isEmpty
        ? '₹' + value.toStringAsFixed(0)
        : value.toStringAsFixed(1) + suffix;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(formatted, style: style),
        ],
      ),
    );
  }
}
