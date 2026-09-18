import 'package:uuid/uuid.dart';

class OrderItem {
  static const List<String> workTypes = [
    'Embroidery',
    'Aari',
  ];

  static const List<String> garmentTypes = [
    'Blouse',
    'Garment piece',
  ];

  final int? id;
  final String uuid;
  final int orderId;
  final String workType;
  final String garmentType;
  final int quantity;
  final int unitPricePaise;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  OrderItem({
    this.id,
    String? uuid,
    required this.orderId,
    required this.workType,
    required this.garmentType,
    required this.quantity,
    required this.unitPricePaise,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  }) : uuid = uuid ?? const Uuid().v4();

  OrderItem copyWith({
    int? id,
    String? uuid,
    int? orderId,
    String? workType,
    String? garmentType,
    int? quantity,
    int? unitPricePaise,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return OrderItem(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      orderId: orderId ?? this.orderId,
      workType: workType ?? this.workType,
      garmentType: garmentType ?? this.garmentType,
      quantity: quantity ?? this.quantity,
      unitPricePaise: unitPricePaise ?? this.unitPricePaise,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'uuid': uuid,
      'order_id': orderId,
      'work_type': workType,
      'garment_type': garmentType,
      'quantity': quantity,
      'unit_price_paise': unitPricePaise,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory OrderItem.fromMap(Map<String, Object?> map) {
    return OrderItem(
      id: map['id'] as int?,
      uuid: map['uuid'] as String,
      orderId: map['order_id'] as int,
      workType: map['work_type'] as String,
      garmentType: map['garment_type'] as String,
      quantity: map['quantity'] as int,
      unitPricePaise: map['unit_price_paise'] as int,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
