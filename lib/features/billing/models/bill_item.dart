import 'package:uuid/uuid.dart';

class BillItem {
  final int? id;
  final String uuid;
  final int billId;
  final String description;
  final double quantity;
  final int ratePaise;
  final int amountPaise;

  BillItem({
    this.id,
    String? uuid,
    required this.billId,
    required this.description,
    required this.quantity,
    required this.ratePaise,
    required this.amountPaise,
  }) : uuid = uuid ?? const Uuid().v4();

  factory BillItem.fromMap(Map<String, Object?> map) {
    return BillItem(
      id: map['id'] as int?,
      uuid: map['uuid'] as String,
      billId: map['bill_id'] as int? ?? 0,
      description: map['description'] as String,
      quantity: (map['quantity'] as num).toDouble(),
      ratePaise: map['rate_paise'] as int,
      amountPaise: map['amount_paise'] as int,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'uuid': uuid,
      'bill_id': billId,
      'description': description,
      'quantity': quantity,
      'rate_paise': ratePaise,
      'amount_paise': amountPaise,
    };
  }
}
