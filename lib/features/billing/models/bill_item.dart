class BillItem {
  final int? id;
  final int billId;
  final String description;
  final double quantity;
  final int ratePaise;
  final int amountPaise;

  const BillItem({
    this.id,
    required this.billId,
    required this.description,
    required this.quantity,
    required this.ratePaise,
    required this.amountPaise,
  });

  factory BillItem.fromMap(Map<String, Object?> map) {
    return BillItem(
      id: map['id'] as int?,
      billId: map['bill_id'] as int,
      description: map['description'] as String,
      quantity: (map['quantity'] as num).toDouble(),
      ratePaise: map['rate_paise'] as int,
      amountPaise: map['amount_paise'] as int,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'bill_id': billId,
      'description': description,
      'quantity': quantity,
      'rate_paise': ratePaise,
      'amount_paise': amountPaise,
    };
  }
}
