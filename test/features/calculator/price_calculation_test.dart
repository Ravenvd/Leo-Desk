import 'package:flutter_test/flutter_test.dart';

import 'package:leo_desk/features/calculator/models/price_calculation.dart';

void main() {
  test('calculates bulk discount and one-time designer fee', () {
    final result = PriceCalculator.calculate(
      const PriceCalculationInput(
        stitches: 13511,
        pieces: 77,
        basePricePerPiece: 100,
        monthlyEbBill: 0,
        monthlyRent: 0,
        deliveryWindow: DeliveryWindow.under24Hours,
      ),
    );

    expect(result.discountPercent, 10);
    expect(result.discountPerPiece, 10);
    expect(result.discountedPricePerPiece, 90);
    expect(result.embroideryTotal, 6930);
    expect(result.designerFee, 200);
    expect(result.totalOrderPrice, 7130);
    expect(result.estimatedMachineMinutesPerPiece, closeTo(16.88875, 0.0001));
    expect(result.totalMachineMinutes, closeTo(1300.43375, 0.001));
    expect(result.requiredHoursPerDay, closeTo(21.6739, 0.001));
    expect(result.overnightRequired, isTrue);
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
          basePricePerPiece: 100,
          monthlyEbBill: 0,
          monthlyRent: 0,
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
          basePricePerPiece: 100,
          monthlyEbBill: 0,
          monthlyRent: 0,
          deliveryWindow: DeliveryWindow.under24Hours,
        ),
      );
      expect(result.designerFee, entry.value);
    }
  });

  test('Aari adds 60 percent before bulk discount', () {
    final result = PriceCalculator.calculate(
      const PriceCalculationInput(
        stitches: 10000,
        pieces: 10,
        basePricePerPiece: 100,
        monthlyEbBill: 0,
        monthlyRent: 0,
        deliveryWindow: DeliveryWindow.under24Hours,
        isAari: true,
      ),
    );

    expect(result.aariAdjustment, 60);
    expect(result.discountPercent, 5);
    expect(result.discountPerPiece, 8);
    expect(result.discountedPricePerPiece, 152);
    expect(result.embroideryTotal, 1520);
    expect(result.designerFee, 200);
    expect(result.totalOrderPrice, 1720);
  });
}
