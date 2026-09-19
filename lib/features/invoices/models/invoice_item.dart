import 'package:uuid/uuid.dart';

class InvoiceItem {
  final int? id;
  final String uuid;
  final int invoiceId;
  final String description;
  final double quantity;
  final int ratePaise;
  final int amountPaise;

  InvoiceItem({
    this.id,
    String? uuid,
    required this.invoiceId,
    required this.description,
    required this.quantity,
    required this.ratePaise,
    required this.amountPaise,
  }) : uuid = uuid ?? const Uuid().v4();

  Map<String, Object?> toMap() => {
        'id': id,
        'uuid': uuid,
        'invoice_id': invoiceId,
        'description': description,
        'quantity': quantity,
        'rate_paise': ratePaise,
        'amount_paise': amountPaise,
      };

  factory InvoiceItem.fromMap(Map<String, Object?> map) => InvoiceItem(
        id: map['id'] as int?,
        uuid: map['uuid'] as String,
        invoiceId: map['invoice_id'] as int,
        description: map['description'] as String,
        quantity: (map['quantity'] as num).toDouble(),
        ratePaise: map['rate_paise'] as int,
        amountPaise: map['amount_paise'] as int,
      );
}
