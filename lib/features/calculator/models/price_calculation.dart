class PriceCalculationInput {
  const PriceCalculationInput({
    required this.stitches,
    required this.ratePerThousandStitches,
    required this.monthlyEbBill,
    required this.monthlyRent,
    this.isAari = false,
    this.isOvernight = false,
    this.machineSpeed = 800,
    this.timeSurchargePercent = 20,
    this.aariSurchargePercent = 60,
    this.ebAllocationPercent = 5,
    this.rentAllocationPercent = 5,
    this.overnightSurchargePercent = 25,
    this.labourPercent = 20,
  });

  final int stitches;
  final double ratePerThousandStitches;
  final double monthlyEbBill;
  final double monthlyRent;
  final bool isAari;
  final bool isOvernight;
  final double machineSpeed;
  final double timeSurchargePercent;
  final double aariSurchargePercent;
  final double ebAllocationPercent;
  final double rentAllocationPercent;
  final double overnightSurchargePercent;
  final double labourPercent;
}

class PriceCalculation {
  const PriceCalculation({
    required this.stitchCharge,
    required this.estimatedMinutes,
    required this.timeSurcharge,
    required this.aariSurcharge,
    required this.workCharge,
    required this.ebAllocation,
    required this.rentAllocation,
    required this.overnightSurcharge,
    required this.labourCharge,
    required this.totalBeforeRounding,
    required this.finalCost,
  });

  final double stitchCharge;
  final double estimatedMinutes;
  final double timeSurcharge;
  final double aariSurcharge;
  final double workCharge;
  final double ebAllocation;
  final double rentAllocation;
  final double overnightSurcharge;
  final double labourCharge;
  final double totalBeforeRounding;
  final double finalCost;
}

class PriceCalculator {
  const PriceCalculator._();

  static PriceCalculation calculate(PriceCalculationInput input) {
    if (input.stitches < 0) {
      throw ArgumentError.value(input.stitches, 'stitches', 'Cannot be negative');
    }
    if (input.machineSpeed <= 0) {
      throw ArgumentError.value(
        input.machineSpeed,
        'machineSpeed',
        'Must be greater than zero',
      );
    }

    final stitchCharge =
        input.stitches / 1000 * input.ratePerThousandStitches;
    final estimatedMinutes = input.stitches / input.machineSpeed;

    final timeSurcharge = estimatedMinutes > 60
        ? stitchCharge * input.timeSurchargePercent / 100
        : 0.0;

    final aariSurcharge = input.isAari
        ? stitchCharge * input.aariSurchargePercent / 100
        : 0.0;

    final workCharge = stitchCharge + timeSurcharge + aariSurcharge;

    final ebAllocation =
        input.monthlyEbBill * input.ebAllocationPercent / 100;
    final rentAllocation =
        input.monthlyRent * input.rentAllocationPercent / 100;

    final overnightSurcharge = input.isOvernight
        ? workCharge * input.overnightSurchargePercent / 100
        : 0.0;

    final labourCharge = workCharge * input.labourPercent / 100;

    final totalBeforeRounding = workCharge +
        ebAllocation +
        rentAllocation +
        overnightSurcharge +
        labourCharge;

    final finalCost = (totalBeforeRounding / 50).round() * 50.0;

    return PriceCalculation(
      stitchCharge: stitchCharge,
      estimatedMinutes: estimatedMinutes,
      timeSurcharge: timeSurcharge,
      aariSurcharge: aariSurcharge,
      workCharge: workCharge,
      ebAllocation: ebAllocation,
      rentAllocation: rentAllocation,
      overnightSurcharge: overnightSurcharge,
      labourCharge: labourCharge,
      totalBeforeRounding: totalBeforeRounding,
      finalCost: finalCost,
    );
  }
}
