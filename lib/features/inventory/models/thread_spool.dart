import 'package:uuid/uuid.dart';

class ThreadSpool {
  static const String syncStatusPending = 'pending';
  static const String syncStatusSynced = 'synced';

  final int? id;
  final String uuid;
  final String syncStatus;
  final int consumableId;
  final String consumableUuid;
  final double approximateLengthM;
  final double remainingPercent;
  final DateTime? purchaseDate;
  final int? purchaseCostPaise;
  final DateTime? emptiedAt;
  final double? estimatedWastagePercent;
  final DateTime createdAt;
  final DateTime updatedAt;

  ThreadSpool({
    this.id,
    String? uuid,
    this.syncStatus = syncStatusPending,
    required this.consumableId,
    required this.consumableUuid,
    required this.approximateLengthM,
    this.remainingPercent = 100,
    this.purchaseDate,
    this.purchaseCostPaise,
    this.emptiedAt,
    this.estimatedWastagePercent,
    required this.createdAt,
    required this.updatedAt,
  }) : uuid = uuid ?? const Uuid().v4() {
    if (approximateLengthM <= 0) {
      throw ArgumentError.value(
        approximateLengthM,
        'approximateLengthM',
        'Must be greater than zero.',
      );
    }
    if (remainingPercent < 0 || remainingPercent > 100) {
      throw ArgumentError.value(
        remainingPercent,
        'remainingPercent',
        'Must be between 0 and 100.',
      );
    }
    if (estimatedWastagePercent != null &&
        (estimatedWastagePercent! < 0 || estimatedWastagePercent! > 100)) {
      throw ArgumentError.value(
        estimatedWastagePercent,
        'estimatedWastagePercent',
        'Must be between 0 and 100.',
      );
    }
  }

  double get estimatedRemainingMetres =>
      approximateLengthM * remainingPercent / 100;

  bool get isLow => remainingPercent < 10;
  bool get isEmpty => emptiedAt != null || remainingPercent == 0;

  ThreadSpool copyWith({
    int? id,
    String? uuid,
    String? syncStatus,
    int? consumableId,
    String? consumableUuid,
    double? approximateLengthM,
    double? remainingPercent,
    DateTime? purchaseDate,
    int? purchaseCostPaise,
    DateTime? emptiedAt,
    double? estimatedWastagePercent,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      ThreadSpool(
        id: id ?? this.id,
        uuid: uuid ?? this.uuid,
        syncStatus: syncStatus ?? this.syncStatus,
        consumableId: consumableId ?? this.consumableId,
        consumableUuid: consumableUuid ?? this.consumableUuid,
        approximateLengthM: approximateLengthM ?? this.approximateLengthM,
        remainingPercent: remainingPercent ?? this.remainingPercent,
        purchaseDate: purchaseDate ?? this.purchaseDate,
        purchaseCostPaise: purchaseCostPaise ?? this.purchaseCostPaise,
        emptiedAt: emptiedAt ?? this.emptiedAt,
        estimatedWastagePercent:
            estimatedWastagePercent ?? this.estimatedWastagePercent,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'uuid': uuid,
        'sync_status': syncStatus,
        'consumable_id': consumableId,
        'consumable_uuid': consumableUuid,
        'approximate_length_m': approximateLengthM,
        'remaining_percent': remainingPercent,
        'purchase_date': purchaseDate?.toIso8601String(),
        'purchase_cost_paise': purchaseCostPaise,
        'emptied_at': emptiedAt?.toIso8601String(),
        'estimated_wastage_percent': estimatedWastagePercent,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ThreadSpool.fromMap(Map<String, Object?> map) => ThreadSpool(
        id: map['id'] as int?,
        uuid: map['uuid'] as String,
        syncStatus: map['sync_status'] as String? ?? syncStatusSynced,
        consumableId: map['consumable_id'] as int,
        consumableUuid: map['consumable_uuid'] as String,
        approximateLengthM:
            (map['approximate_length_m'] as num).toDouble(),
        remainingPercent:
            (map['remaining_percent'] as num?)?.toDouble() ?? 100,
        purchaseDate: map['purchase_date'] == null
            ? null
            : DateTime.parse(map['purchase_date'] as String),
        purchaseCostPaise: map['purchase_cost_paise'] as int?,
        emptiedAt: map['emptied_at'] == null
            ? null
            : DateTime.parse(map['emptied_at'] as String),
        estimatedWastagePercent:
            (map['estimated_wastage_percent'] as num?)?.toDouble(),
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}
