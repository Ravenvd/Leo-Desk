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
    required this.basePricePerPiece,
    required this.monthlyEbBill,
    required this.monthlyRent,
    required this.deliveryWindow,
    this.isAari = false,
    this.machineSpeed = 800,
  });

  final int stitches;
  final int pieces;
  final double basePricePerPiece;
  final double monthlyEbBill;
  final double monthlyRent;
  final DeliveryWindow deliveryWindow;
  final bool isAari;
  final double machineSpeed;
}

class PriceCalculation {
  const PriceCalculation({
    required this.designerFee,
    required this.discountPercent,
    required this.discountPerPiece,
    required this.discountedPricePerPiece,
    required this.embroideryTotal,
    required this.totalOrderPrice,
    required this.estimatedMachineMinutesPerPiece,
    required this.totalMachineMinutes,
    required this.requiredHoursPerDay,
    required this.overnightRequired,
  });

  final double designerFee;
  final double discountPercent;
  final double discountPerPiece;
  final double discountedPricePerPiece;
  final double embroideryTotal;
  final double totalOrderPrice;
  final double estimatedMachineMinutesPerPiece;
  final double totalMachineMinutes;
  final double requiredHoursPerDay;
  final bool overnightRequired;
}

class PriceCalculator {
  const PriceCalculator._();

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
    if (input.basePricePerPiece < 0) {
      throw ArgumentError.value(
        input.basePricePerPiece,
        'basePricePerPiece',
        'Cannot be negative',
      );
    }
    if (input.machineSpeed <= 0) {
      throw ArgumentError.value(
        input.machineSpeed,
        'machineSpeed',
        'Must be greater than zero',
      );
    }

    final discountPercent = _bulkDiscountPercent(input.pieces);
    final discountPerPiece =
        input.basePricePerPiece * discountPercent / 100;
    final discountedPricePerPiece =
        input.basePricePerPiece - discountPerPiece;
    final embroideryTotal =
        discountedPricePerPiece * input.pieces;

    final designerFee = _designerFee(input.stitches);
    final totalOrderPrice = embroideryTotal + designerFee;

    final estimatedMachineMinutesPerPiece =
        input.stitches / input.machineSpeed;
    final totalMachineMinutes =
        estimatedMachineMinutesPerPiece * input.pieces;
    final requiredHoursPerDay =
        totalMachineMinutes / 60 / input.deliveryWindow.availableDays;
    final overnightRequired = requiredHoursPerDay > 12;

    return PriceCalculation(
      designerFee: designerFee,
      discountPercent: discountPercent,
      discountPerPiece: discountPerPiece,
      discountedPricePerPiece: discountedPricePerPiece,
      embroideryTotal: embroideryTotal,
      totalOrderPrice: totalOrderPrice,
      estimatedMachineMinutesPerPiece: estimatedMachineMinutesPerPiece,
      totalMachineMinutes: totalMachineMinutes,
      requiredHoursPerDay: requiredHoursPerDay,
      overnightRequired: overnightRequired,
    );
  }
}
