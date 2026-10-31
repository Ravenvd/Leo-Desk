import 'package:uuid/uuid.dart';

class MaintenanceRecord {
  static const String syncStatusPending = 'pending';
  static const String syncStatusSynced = 'synced';
  static const String syncStatusDeletedPending = 'deleted_pending';

  final int? id;
  final String uuid;
  final String syncStatus;
  final int assetId;
  final String assetUuid;
  final DateTime maintenanceDate;
  final String description;
  final int costPaise;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  MaintenanceRecord({
    this.id,
    String? uuid,
    this.syncStatus = syncStatusPending,
    required this.assetId,
    required this.assetUuid,
    required this.maintenanceDate,
    required this.description,
    this.costPaise = 0,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  }) : uuid = uuid ?? const Uuid().v4();

  MaintenanceRecord copyWith({
    int? id,
    String? uuid,
    String? syncStatus,
    int? assetId,
    String? assetUuid,
    DateTime? maintenanceDate,
    String? description,
    int? costPaise,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MaintenanceRecord(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      syncStatus: syncStatus ?? this.syncStatus,
      assetId: assetId ?? this.assetId,
      assetUuid: assetUuid ?? this.assetUuid,
      maintenanceDate: maintenanceDate ?? this.maintenanceDate,
      description: description ?? this.description,
      costPaise: costPaise ?? this.costPaise,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'uuid': uuid,
        'sync_status': syncStatus,
        'asset_id': assetId,
        'asset_uuid': assetUuid,
        'maintenance_date': maintenanceDate.toIso8601String(),
        'description': description,
        'cost_paise': costPaise,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory MaintenanceRecord.fromMap(Map<String, Object?> map) {
    return MaintenanceRecord(
      id: map['id'] as int?,
      uuid: map['uuid'] as String,
      syncStatus: map['sync_status'] as String? ?? syncStatusSynced,
      assetId: map['asset_id'] as int,
      assetUuid: map['asset_uuid'] as String,
      maintenanceDate: DateTime.parse(map['maintenance_date'] as String),
      description: map['description'] as String,
      costPaise: map['cost_paise'] as int? ?? 0,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
