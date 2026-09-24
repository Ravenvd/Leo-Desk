import 'package:flutter_test/flutter_test.dart';

import 'package:leo_desk/features/calculator/models/price_calculation.dart';

void main() {
  test('calculates normal embroidery and rounds to nearest 50', () {
    final result = PriceCalculator.calculate(
      const PriceCalculationInput(
        stitches: 25000,
        ratePerThousandStitches: 20,
        monthlyEbBill: 3000,
        monthlyRent: 10000,
      ),
    );

    expect(result.estimatedMinutes, 31.25);
    expect(result.stitchCharge, 500);
    expect(result.timeSurcharge, 0);
    expect(result.aariSurcharge, 0);
    expect(result.workCharge, 500);
    expect(result.ebAllocation, 150);
    expect(result.rentAllocation, 500);
    expect(result.labourCharge, 100);
    expect(result.overnightSurcharge, 0);
    expect(result.totalBeforeRounding, 1250);
    expect(result.finalCost, 1250);
  });

  test('adds time surcharge after one hour', () {
    final result = PriceCalculator.calculate(
      const PriceCalculationInput(
        stitches: 60000,
        ratePerThousandStitches: 20,
        monthlyEbBill: 0,
        monthlyRent: 0,
      ),
    );

    expect(result.estimatedMinutes, 75);
    expect(result.stitchCharge, 1200);
    expect(result.timeSurcharge, 240);
    expect(result.workCharge, 1440);
    expect(result.labourCharge, 288);
  });

  test('adds Aari surcharge and overnight surcharge', () {
    final result = PriceCalculator.calculate(
      const PriceCalculationInput(
        stitches: 10000,
        ratePerThousandStitches: 20,
        monthlyEbBill: 2000,
        monthlyRent: 5000,
        isAari: true,
        isOvernight: true,
      ),
    );

    expect(result.stitchCharge, 200);
    expect(result.aariSurcharge, 120);
    expect(result.workCharge, 320);
    expect(result.ebAllocation, 100);
    expect(result.rentAllocation, 250);
    expect(result.overnightSurcharge, 80);
    expect(result.labourCharge, 64);
    expect(result.totalBeforeRounding, 814);
    expect(result.finalCost, 800);
  });

  test('rounds to the nearest 50', () {
    final low = PriceCalculator.calculate(
      const PriceCalculationInput(
        stitches: 1000,
        ratePerThousandStitches: 21,
        monthlyEbBill: 0,
        monthlyRent: 0,
      ),
    );
    final high = PriceCalculator.calculate(
      const PriceCalculationInput(
        stitches: 1000,
        ratePerThousandStitches: 29,
        monthlyEbBill: 0,
        monthlyRent: 0,
      ),
    );

    expect(low.finalCost, 20);
    expect(high.finalCost, 30);
  });
}
