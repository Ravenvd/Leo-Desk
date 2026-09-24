import 'package:flutter_test/flutter_test.dart';

import 'package:leo_desk/features/calculator/models/price_calculation.dart';

void main() {
  test('calculates normal embroidery with fixed rate of 40', () {
    final result = PriceCalculator.calculate(
      const PriceCalculationInput(
        stitches: 25000,
        pieces: 2,
        timePerPieceMinutes: 20,
        monthlyEbBill: 3000,
        monthlyRent: 10000,
        deliveryWindow: DeliveryWindow.under24Hours,
      ),
    );

    expect(result.estimatedMachineMinutes, 31.25);
    expect(result.totalWorkMinutes, 40);
    expect(result.requiredHoursPerDay, closeTo(0.6667, 0.001));
    expect(result.overnightRequired, isFalse);
    expect(result.stitchCharge, 1000);
    expect(result.timeSurcharge, 0);
    expect(result.workCharge, 1000);
    expect(result.ebAllocation, 150);
    expect(result.rentAllocation, 500);
    expect(result.labourCharge, 200);
    expect(result.overnightSurcharge, 0);
    expect(result.totalBeforeRounding, 1850);
    expect(result.finalCost, 1850);
  });

  test('adds time surcharge after one hour of maximum work time', () {
    final result = PriceCalculator.calculate(
      const PriceCalculationInput(
        stitches: 60000,
        pieces: 6,
        timePerPieceMinutes: 15,
        monthlyEbBill: 0,
        monthlyRent: 0,
        deliveryWindow: DeliveryWindow.under24Hours,
      ),
    );

    expect(result.totalWorkMinutes, 90);
    expect(result.estimatedMachineMinutes, 75);
    expect(result.timeSurcharge, 480);
    expect(result.workCharge, 2880);
    expect(result.labourCharge, 576);
  });

  test('automatically applies overnight when daily work exceeds 12 hours', () {
    final result = PriceCalculator.calculate(
      const PriceCalculationInput(
        stitches: 10000,
        pieces: 100,
        timePerPieceMinutes: 10,
        monthlyEbBill: 2000,
        monthlyRent: 5000,
        deliveryWindow: DeliveryWindow.under24Hours,
      ),
    );

    expect(result.totalWorkMinutes, 1000);
    expect(result.requiredHoursPerDay, closeTo(16.6667, 0.001));
    expect(result.overnightRequired, isTrue);
    expect(result.stitchCharge, 400);
    expect(result.workCharge, 480);
    expect(result.ebAllocation, 100);
    expect(result.rentAllocation, 250);
    expect(result.overnightSurcharge, 120);
    expect(result.labourCharge, 96);
    expect(result.totalBeforeRounding, 1046);
    expect(result.finalCost, 1050);
  });

  test('24-48 hour delivery spreads work over two days', () {
    final result = PriceCalculator.calculate(
      const PriceCalculationInput(
        stitches: 10000,
        pieces: 100,
        timePerPieceMinutes: 10,
        monthlyEbBill: 0,
        monthlyRent: 0,
        deliveryWindow: DeliveryWindow.from24To48Hours,
      ),
    );

    expect(result.requiredHoursPerDay, closeTo(8.3333, 0.001));
    expect(result.overnightRequired, isFalse);
  });

  test('Aari adds 60 percent and rounds to nearest 50', () {
    final result = PriceCalculator.calculate(
      const PriceCalculationInput(
        stitches: 10000,
        pieces: 1,
        timePerPieceMinutes: 30,
        monthlyEbBill: 0,
        monthlyRent: 0,
        deliveryWindow: DeliveryWindow.under24Hours,
        isAari: true,
      ),
    );

    expect(result.stitchCharge, 400);
    expect(result.aariSurcharge, 240);
    expect(result.workCharge, 640);
    expect(result.labourCharge, 128);
    expect(result.totalBeforeRounding, 768);
    expect(result.finalCost, 750);
  });

  test('rounds to the nearest 50', () {
    final low = PriceCalculator.calculate(
      const PriceCalculationInput(
        stitches: 1000,
        pieces: 1,
        timePerPieceMinutes: 1,
        monthlyEbBill: 0,
        monthlyRent: 0,
        deliveryWindow: DeliveryWindow.under24Hours,
      ),
    );
    final high = PriceCalculator.calculate(
      const PriceCalculationInput(
        stitches: 1000,
        pieces: 1,
        timePerPieceMinutes: 1,
        monthlyEbBill: 0,
        monthlyRent: 0,
        deliveryWindow: DeliveryWindow.under24Hours,
      ),
    );

    expect(low.finalCost, 50);
    expect(high.finalCost, 100);
  });
}
