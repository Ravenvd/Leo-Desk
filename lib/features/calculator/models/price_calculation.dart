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
    required this.monthlyEbBill,
    required this.monthlyRent,
    required this.deliveryWindow,
    this.isAari = false,
  });

  final int stitches;
  final int pieces;
  final double monthlyEbBill;
  final double monthlyRent;
  final DeliveryWindow deliveryWindow;
  final bool isAari;
}

class PriceCalculation {
  const PriceCalculation({
    required this.pieces,
    required this.machineRatePerHour,
    required this.machineSpeed,
    required this.baseProductionPricePerPiece,
    required this.aariAdjustment,
    required this.ebAllocation,
    required this.rentAllocation,
    required this.designerFee,
    required this.discountPercent,
    required this.discountPerPiece,
    required this.discountedProductionPricePerPiece,
    required this.finalPricePerPiece,
    required this.embroideryTotal,
    required this.totalOrderPrice,
    required this.estimatedMachineMinutesPerPiece,
    required this.totalMachineMinutes,
    required this.requiredHoursPerDay,
    required this.overnightRequired,
  });

  final int pieces;
  final double machineRatePerHour;
  final double machineSpeed;
  final double baseProductionPricePerPiece;
  final double aariAdjustment;
  final double ebAllocation;
  final double rentAllocation;
  final double designerFee;
  final double discountPercent;
  final double discountPerPiece;
  final double discountedProductionPricePerPiece;
  final double finalPricePerPiece;
  final double embroideryTotal;
  final double totalOrderPrice;
  final double estimatedMachineMinutesPerPiece;
  final double totalMachineMinutes;
  final double requiredHoursPerDay;
  final bool overnightRequired;
}

class PriceCalculator {
  const PriceCalculator._();

  // Standard Leo Stitch & Design pricing constants.
  // Derived from the current 12-month recovery model:
  // ₹10L loan + 8% interest + wages/rent at 275 productive hours/month,
  // with a 15% profit target.
  static const double standardMachineRatePerHour = 460;
  static const double normalEffectiveSpm = 550;
  static const double aariEffectiveSpm = 300;
  static const double ebAllocationPercent = 5;
  static const double rentAllocationPercent = 5;
  static const double aariSurchargePercent = 60;

  static double _bulkDiscountPercent(int pieces) {
    if (pieces >= 40) return 10;
    if (pieces >= 30) return 9;
    if (pieces >= 20) return 7;
    if (pieces >= 10) return 5;
    if (pieces >= 5) return 2;
    return 0;
  }

  static double _designerFee(int stitches) {
    if (stitches < 10000) return 100;
    if (stitches < 20000) return 200;
    if (stitches < 30000) return 300;
    if (stitches < 40000) return 400;
    return 500;
  }

  static PriceCalculation calculate(PriceCalculationInput input) {
    if (input.stitches <= 0) {
      throw ArgumentError.value(
        input.stitches,
        'stitches',
        'Must be greater than zero',
      );
    }
    if (input.pieces <= 0) {
      throw ArgumentError.value(
        input.pieces,
        'pieces',
        'Must be greater than zero',
      );
    }
    if (input.monthlyEbBill < 0) {
      throw ArgumentError.value(
        input.monthlyEbBill,
        'monthlyEbBill',
        'Cannot be negative',
      );
    }
    if (input.monthlyRent < 0) {
      throw ArgumentError.value(
        input.monthlyRent,
        'monthlyRent',
        'Cannot be negative',
      );
    }

    final machineSpeed =
        input.isAari ? aariEffectiveSpm : normalEffectiveSpm;
    final estimatedMachineMinutesPerPiece = input.stitches / machineSpeed;
    final baseProductionPricePerPiece =
        estimatedMachineMinutesPerPiece / 60 * standardMachineRatePerHour;

    final aariAdjustment = input.isAari
        ? baseProductionPricePerPiece * aariSurchargePercent / 100
        : 0.0;
    final adjustedProductionPricePerPiece =
        baseProductionPricePerPiece + aariAdjustment;

    final discountPercent = _bulkDiscountPercent(input.pieces);
    final discountPerPiece =
        adjustedProductionPricePerPiece * discountPercent / 100;
    final discountedProductionPricePerPiece =
        adjustedProductionPricePerPiece - discountPerPiece;

    // EB and rent are allocated separately from the production charge.
    // They are one-time order allocations, not per-piece additions.
    final ebAllocation = input.monthlyEbBill * ebAllocationPercent / 100;
    final rentAllocation = input.monthlyRent * rentAllocationPercent / 100;

    final designerFee = _designerFee(input.stitches);
    final finalPricePerPiece =
        discountedProductionPricePerPiece +
        (ebAllocation + rentAllocation + designerFee) / input.pieces;
    final embroideryTotal = discountedProductionPricePerPiece * input.pieces;
    final totalOrderPrice =
        embroideryTotal + ebAllocation + rentAllocation + designerFee;

    final totalMachineMinutes =
        estimatedMachineMinutesPerPiece * input.pieces;
    final requiredHoursPerDay =
        totalMachineMinutes / 60 / input.deliveryWindow.availableDays;
    final overnightRequired = requiredHoursPerDay > 12;

    return PriceCalculation(
      pieces: input.pieces,
      machineRatePerHour: standardMachineRatePerHour,
      machineSpeed: machineSpeed,
      baseProductionPricePerPiece: baseProductionPricePerPiece,
      aariAdjustment: aariAdjustment,
      ebAllocation: ebAllocation,
      rentAllocation: rentAllocation,
      designerFee: designerFee,
      discountPercent: discountPercent,
      discountPerPiece: discountPerPiece,
      discountedProductionPricePerPiece: discountedProductionPricePerPiece,
      finalPricePerPiece: finalPricePerPiece,
      embroideryTotal: embroideryTotal,
      totalOrderPrice: totalOrderPrice,
      estimatedMachineMinutesPerPiece: estimatedMachineMinutesPerPiece,
      totalMachineMinutes: totalMachineMinutes,
      requiredHoursPerDay: requiredHoursPerDay,
      overnightRequired: overnightRequired,
    );
  }
}
