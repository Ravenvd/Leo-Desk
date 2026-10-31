import 'package:uuid/uuid.dart';

class InventoryActivity {
  static const String purchase = 'purchase';
  static const String openingStock = 'opening_stock';
  static const String threadUsage = 'thread_usage';
  static const String threadExhausted = 'thread_exhausted';
  static const String stockObservation = 'stock_observation';
  static const String stockAdjustment = 'stock_adjustment';

  static const List<String> activityTypes = [
    purchase,
    openingStock,
    threadUsage,
    threadExhausted,
    stockObservation,
    stockAdjustment,
  ];

  final int? id;
  final String uuid;
  final String syncStatus;
  final int consumableId;
  final String consumableUuid;
  final int? spoolId;
  final String? spoolUuid;
  final int? orderId;
  final String? orderUuid;
  final String activityType;
  final double? quantity;
  final String? unit;
  final double? beforeQuantity;
  final double? afterQuantity;
  final double? observedChange;
  final int? totalCostPaise;
  final double? estimatedWastagePercent;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  InventoryActivity({
    this.id,
    String? uuid,
    this.syncStatus = 'pending',
    required this.consumableId,
    required this.consumableUuid,
    this.spoolId,
    this.spoolUuid,
    this.orderId,
    this.orderUuid,
    required this.activityType,
    this.quantity,
    this.unit,
    this.beforeQuantity,
    this.afterQuantity,
    this.observedChange,
    this.totalCostPaise,
    this.estimatedWastagePercent,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  }) : uuid = uuid ?? const Uuid().v4() {
    if (!activityTypes.contains(activityType)) {
      throw ArgumentError.value(activityType, 'activityType', 'Unsupported activity type.');
    }
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'uuid': uuid,
        'sync_status': syncStatus,
        'consumable_id': consumableId,
        'consumable_uuid': consumableUuid,
        'spool_id': spoolId,
        'spool_uuid': spoolUuid,
        'order_id': orderId,
        'order_uuid': orderUuid,
        'activity_type': activityType,
        'quantity': quantity,
        'unit': unit,
        'before_quantity': beforeQuantity,
        'after_quantity': afterQuantity,
        'observed_change': observedChange,
        'total_cost_paise': totalCostPaise,
        'estimated_wastage_percent': estimatedWastagePercent,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory InventoryActivity.fromMap(Map<String, Object?> map) =>
      InventoryActivity(
        id: map['id'] as int?,
        uuid: map['uuid'] as String,
        syncStatus: map['sync_status'] as String? ?? 'synced',
        consumableId: map['consumable_id'] as int,
        consumableUuid: map['consumable_uuid'] as String,
        spoolId: map['spool_id'] as int?,
        spoolUuid: map['spool_uuid'] as String?,
        orderId: map['order_id'] as int?,
        orderUuid: map['order_uuid'] as String?,
        activityType: map['activity_type'] as String,
        quantity: (map['quantity'] as num?)?.toDouble(),
        unit: map['unit'] as String?,
        beforeQuantity: (map['before_quantity'] as num?)?.toDouble(),
        afterQuantity: (map['after_quantity'] as num?)?.toDouble(),
        observedChange: (map['observed_change'] as num?)?.toDouble(),
        totalCostPaise: map['total_cost_paise'] as int?,
        estimatedWastagePercent:
            (map['estimated_wastage_percent'] as num?)?.toDouble(),
        notes: map['notes'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}
