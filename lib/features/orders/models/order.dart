import 'package:uuid/uuid.dart';

class Order {
  static const List<String> statuses = [
    'New',
    'In Progress',
    'Sent for Stitching',
    'Ready',
    'Completed',
    'Cancelled',
  ];

  final int? id;
  final String uuid;
  final String syncStatus;
  final String orderNumber;
  final int customerId;
  final DateTime orderDate;
  final DateTime expectedDeliveryDate;
  final bool stitchingRequired;
  final String status;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Order({
    this.id,
    String? uuid,
    this.syncStatus = 'pending',
    required this.orderNumber,
    required this.customerId,
    required this.orderDate,
    required this.expectedDeliveryDate,
    required this.stitchingRequired,
    this.status = 'New',
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  }) : uuid = uuid ?? const Uuid().v4();

  Order copyWith({
    int? id,
    String? uuid,
    String? syncStatus,
    String? orderNumber,
    int? customerId,
    DateTime? orderDate,
    DateTime? expectedDeliveryDate,
    bool? stitchingRequired,
    String? status,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Order(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      syncStatus: syncStatus ?? this.syncStatus,
      orderNumber: orderNumber ?? this.orderNumber,
      customerId: customerId ?? this.customerId,
      orderDate: orderDate ?? this.orderDate,
      expectedDeliveryDate:
          expectedDeliveryDate ?? this.expectedDeliveryDate,
      stitchingRequired: stitchingRequired ?? this.stitchingRequired,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'uuid': uuid,
      'sync_status': syncStatus,
      'order_number': orderNumber,
      'customer_id': customerId,
      'order_date': orderDate.toIso8601String(),
      'expected_delivery_date': expectedDeliveryDate.toIso8601String(),
      'stitching_required': stitchingRequired ? 1 : 0,
      'status': status,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Order.fromMap(Map<String, Object?> map) {
    return Order(
      id: map['id'] as int?,
      uuid: map['uuid'] as String,
      syncStatus: map['sync_status'] as String? ?? 'synced',
      orderNumber: map['order_number'] as String,
      customerId: map['customer_id'] as int,
      orderDate: DateTime.parse(map['order_date'] as String),
      expectedDeliveryDate:
          DateTime.parse(map['expected_delivery_date'] as String),
      stitchingRequired: (map['stitching_required'] as int) == 1,
      status: map['status'] as String? ?? 'New',
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
