import 'package:flutter_test/flutter_test.dart';

import 'package:leo_desk/features/calculator/models/price_calculation.dart';

void main() {
  test('uses the conservative 232-hour business model', () {
    final result = PriceCalculator.calculate(
      const PriceCalculationInput(
        stitches: 13000,
        pieces: 1,
        monthlyEbBill: 1000,
        monthlyRent: 4500,
        deliveryWindow: DeliveryWindow.under24Hours,
      ),
    );

    expect(result.machineSpeed, 550);
    expect(result.monthlyOperatingHours, 232);
    expect(result.monthlyOperatingCost, closeTo(27166.6667, 0.001));
    expect(result.productionCostPerHour, closeTo(117.0977, 0.001));
    expect(result.sellingRatePerHour, closeTo(154.8618, 0.001));
    expect(result.estimatedMachineMinutesPerPiece, closeTo(23.63636, 0.0001));
    expect(result.baseProductionPricePerPiece, closeTo(61.0113, 0.001));
    expect(result.designerFee, 200);
    expect(result.totalOrderPrice, closeTo(261.0113, 0.001));
    expect(result.monthlyRevenueTarget, closeTo(146137.5, 0.01));
    expect(result.targetRevenuePerHour, closeTo(629.9030, 0.001));
  });

  test('uses 300 SPM and 60 percent surcharge for Aari', () {
    final result = PriceCalculator.calculate(
      const PriceCalculationInput(
        stitches: 13000,
        pieces: 1,
        monthlyEbBill: 1000,
        monthlyRent: 4500,
        deliveryWindow: DeliveryWindow.under24Hours,
        isAari: true,
      ),
    );

    expect(result.machineSpeed, 300);
    expect(result.estimatedMachineMinutesPerPiece, closeTo(43.3333, 0.001));
    expect(result.baseProductionPricePerPiece, closeTo(111.8560, 0.001));
    expect(result.aariAdjustment, closeTo(67.1136, 0.001));
    expect(result.discountedProductionPricePerPiece, closeTo(178.9696, 0.001));
  });

  test('calculates the 13,511-stitch 77-piece test order', () {
    final result = PriceCalculator.calculate(
      const PriceCalculationInput(
        stitches: 13511,
        pieces: 77,
        monthlyEbBill: 1000,
        monthlyRent: 4500,
        deliveryWindow: DeliveryWindow.under24Hours,
      ),
    );

    expect(result.discountPercent, 10);
    expect(result.designerFee, 200);
    expect(result.estimatedMachineMinutesPerPiece, closeTo(24.56545, 0.0001));
    expect(result.embroideryTotal, closeTo(4395.05, 0.01));
    expect(result.totalOrderPrice, closeTo(4595.05, 0.01));
  });

  test('applies each bulk discount tier', () {
    final tiers = <int, double>{
      1: 0,
      4: 0,
      5: 2,
      9: 2,
      10: 5,
      19: 5,
      20: 7,
      29: 7,
      30: 9,
      39: 9,
      40: 10,
      77: 10,
    };

    for (final entry in tiers.entries) {
      final result = PriceCalculator.calculate(
        PriceCalculationInput(
          stitches: 5000,
          pieces: entry.key,
          monthlyEbBill: 1000,
          monthlyRent: 4500,
          deliveryWindow: DeliveryWindow.under24Hours,
        ),
      );
      expect(result.discountPercent, entry.value);
    }
  });

  test('applies designer fee by stitch count', () {
    final expected = <int, double>{
      9999: 100,
      10000: 200,
      19999: 200,
      20000: 300,
      29999: 300,
      30000: 400,
      39999: 400,
      40000: 500,
    };

    for (final entry in expected.entries) {
      final result = PriceCalculator.calculate(
        PriceCalculationInput(
          stitches: entry.key,
          pieces: 1,
          monthlyEbBill: 1000,
          monthlyRent: 4500,
          deliveryWindow: DeliveryWindow.under24Hours,
        ),
      );
      expect(result.designerFee, entry.value);
    }
  });
}
