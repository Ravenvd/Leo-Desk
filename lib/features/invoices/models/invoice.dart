import 'package:uuid/uuid.dart';

class Invoice {
  final int? id;
  final String uuid;
  final String syncStatus;
  final int orderId;
  final String orderUuid;
  final int customerId;
  final String? customerUuid;
  final String invoiceNumber;
  final DateTime invoiceDate;
  final int subtotalPaise;
  final int totalPaise;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Invoice({
    this.id,
    String? uuid,
    this.syncStatus = 'pending',
    required this.orderId,
    required this.orderUuid,
    required this.customerId,
    this.customerUuid,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.subtotalPaise,
    required this.totalPaise,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  }) : uuid = uuid ?? const Uuid().v4();

  Invoice copyWith({
    int? id,
    String? uuid,
    String? syncStatus,
    int? orderId,
    String? orderUuid,
    int? customerId,
    String? customerUuid,
    String? invoiceNumber,
    DateTime? invoiceDate,
    int? subtotalPaise,
    int? totalPaise,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Invoice(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      syncStatus: syncStatus ?? this.syncStatus,
      orderId: orderId ?? this.orderId,
      orderUuid: orderUuid ?? this.orderUuid,
      customerId: customerId ?? this.customerId,
      customerUuid: customerUuid ?? this.customerUuid,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      subtotalPaise: subtotalPaise ?? this.subtotalPaise,
      totalPaise: totalPaise ?? this.totalPaise,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'uuid': uuid,
        'sync_status': syncStatus,
        'order_id': orderId,
        'order_uuid': orderUuid,
        'customer_id': customerId,
        'customer_uuid': customerUuid,
        'invoice_number': invoiceNumber,
        'invoice_date': invoiceDate.toIso8601String(),
        'subtotal_paise': subtotalPaise,
        'total_paise': totalPaise,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Invoice.fromMap(Map<String, Object?> map) => Invoice(
        id: map['id'] as int?,
        uuid: map['uuid'] as String,
        syncStatus: map['sync_status'] as String? ?? 'synced',
        orderId: map['order_id'] as int,
        orderUuid: map['order_uuid'] as String,
        customerId: map['customer_id'] as int,
        customerUuid: map['customer_uuid'] as String?,
        invoiceNumber: map['invoice_number'] as String,
        invoiceDate: DateTime.parse(map['invoice_date'] as String),
        subtotalPaise: map['subtotal_paise'] as int,
        totalPaise: map['total_paise'] as int,
        notes: map['notes'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}
