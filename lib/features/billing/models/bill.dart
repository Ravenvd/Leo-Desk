class Bill {
  final int? id;
  final int customerId;
  final String billNumber;
  final DateTime billDate;
  final int subtotalPaise;
  final int discountPaise;
  final int taxPaise;
  final int totalPaise;
  final int amountPaidPaise;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Bill({
    this.id,
    required this.customerId,
    required this.billNumber,
    required this.billDate,
    required this.subtotalPaise,
    this.discountPaise = 0,
    this.taxPaise = 0,
    required this.totalPaise,
    this.amountPaidPaise = 0,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  int get balanceDuePaise => totalPaise - amountPaidPaise;

  String get paymentStatus {
    if (amountPaidPaise <= 0) return 'unpaid';
    if (amountPaidPaise >= totalPaise) return 'paid';
    return 'partial';
  }

  Bill copyWith({
    int? id,
    int? customerId,
    String? billNumber,
    DateTime? billDate,
    int? subtotalPaise,
    int? discountPaise,
    int? taxPaise,
    int? totalPaise,
    int? amountPaidPaise,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Bill(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      billNumber: billNumber ?? this.billNumber,
      billDate: billDate ?? this.billDate,
      subtotalPaise: subtotalPaise ?? this.subtotalPaise,
      discountPaise: discountPaise ?? this.discountPaise,
      taxPaise: taxPaise ?? this.taxPaise,
      totalPaise: totalPaise ?? this.totalPaise,
      amountPaidPaise: amountPaidPaise ?? this.amountPaidPaise,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'customer_id': customerId,
      'bill_number': billNumber,
      'bill_date': billDate.toIso8601String(),
      'subtotal_paise': subtotalPaise,
      'discount_paise': discountPaise,
      'tax_paise': taxPaise,
      'total_paise': totalPaise,
      'amount_paid_paise': amountPaidPaise,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Bill.fromMap(Map<String, Object?> map) {
    return Bill(
      id: map['id'] as int?,
      customerId: map['customer_id'] as int,
      billNumber: map['bill_number'] as String,
      billDate: DateTime.parse(map['bill_date'] as String),
      subtotalPaise: map['subtotal_paise'] as int,
      discountPaise: map['discount_paise'] as int,
      taxPaise: map['tax_paise'] as int,
      totalPaise: map['total_paise'] as int,
      amountPaidPaise: map['amount_paid_paise'] as int,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
