enum DeliveryWindow {
  under24Hours,
  from24To48Hours,
  over48Hours,
}

extension DeliveryWindowX on DeliveryWindow {
  int get availableDays {
    switch (this) {
      case DeliveryWindow.under24Hours:
        return 1;
      case DeliveryWindow.from24To48Hours:
        return 2;
      case DeliveryWindow.over48Hours:
        return 3;
    }
  }

  String get label {
    switch (this) {
      case DeliveryWindow.under24Hours:
        return '<24 hrs';
      case DeliveryWindow.from24To48Hours:
        return '24–48 hrs';
      case DeliveryWindow.over48Hours:
        return '>48 hrs';
    }
  }
}

class PriceCalculationInput {
  const PriceCalculationInput({
    required this.stitches,
    required this.pieces,
    required this.timePerPieceMinutes,
    required this.monthlyEbBill,
    required this.monthlyRent,
    required this.deliveryWindow,
    this.isAari = false,
    this.machineSpeed = 800,
    this.timeSurchargePercent = 20,
    this.aariSurchargePercent = 60,
    this.ebAllocationPercent = 5,
    this.rentAllocationPercent = 5,
    this.overnightSurchargePercent = 25,
    this.labourPercent = 20,
  });

  final int stitches;
  final int pieces;
  final double timePerPieceMinutes;
  final double monthlyEbBill;
  final double monthlyRent;
  final DeliveryWindow deliveryWindow;
  final bool isAari;
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
    required this.estimatedMachineMinutes,
    required this.totalWorkMinutes,
    required this.requiredHoursPerDay,
    required this.overnightRequired,
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
  final double estimatedMachineMinutes;
  final double totalWorkMinutes;
  final double requiredHoursPerDay;
  final bool overnightRequired;
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
    if (input.pieces <= 0) {
      throw ArgumentError.value(input.pieces, 'pieces', 'Must be greater than zero');
    }
    if (input.timePerPieceMinutes <= 0) {
      throw ArgumentError.value(
        input.timePerPieceMinutes,
        'timePerPieceMinutes',
        'Must be greater than zero',
      );
    }
    if (input.machineSpeed <= 0) {
      throw ArgumentError.value(
        input.machineSpeed,
        'machineSpeed',
        'Must be greater than zero',
      );
    }

    const ratePerThousandStitches = 40.0;
    final stitchCharge = input.stitches / 1000 * ratePerThousandStitches;
    final estimatedMachineMinutes = input.stitches / input.machineSpeed;

    final totalWorkMinutes = input.pieces * input.timePerPieceMinutes;
    final requiredHoursPerDay =
        totalWorkMinutes / 60 / input.deliveryWindow.availableDays;
    final overnightRequired = requiredHoursPerDay > 12;

    final timeSurcharge = totalWorkMinutes > 60
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

    final overnightSurcharge = overnightRequired
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
      estimatedMachineMinutes: estimatedMachineMinutes,
      totalWorkMinutes: totalWorkMinutes,
      requiredHoursPerDay: requiredHoursPerDay,
      overnightRequired: overnightRequired,
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
