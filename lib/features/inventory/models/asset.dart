import 'package:uuid/uuid.dart';

class Asset {
  static const String syncStatusPending = 'pending';
  static const String syncStatusSynced = 'synced';
  static const String syncStatusDeletedPending = 'deleted_pending';

  static const String statusActive = 'Active';
  static const String statusMaintenance = 'Under maintenance';
  static const String statusInactive = 'Inactive';
  static const String statusCondemned = 'Condemned';

  static const List<String> statuses = [
    statusActive,
    statusMaintenance,
    statusInactive,
    statusCondemned,
  ];

  final int? id;
  final String uuid;
  final String syncStatus;
  final String assetCode;
  final String name;
  final DateTime? purchaseDate;
  final int? purchaseCostPaise;
  final String? manufacturerModel;
  final String? serialNumber;
  final String? warrantyInformation;
  final String status;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Asset({
    this.id,
    String? uuid,
    this.syncStatus = syncStatusPending,
    required this.assetCode,
    required this.name,
    this.purchaseDate,
    this.purchaseCostPaise,
    this.manufacturerModel,
    this.serialNumber,
    this.warrantyInformation,
    this.status = statusActive,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  }) : uuid = uuid ?? const Uuid().v4();

  Asset copyWith({
    int? id,
    String? uuid,
    String? syncStatus,
    String? assetCode,
    String? name,
    DateTime? purchaseDate,
    int? purchaseCostPaise,
    String? manufacturerModel,
    String? serialNumber,
    String? warrantyInformation,
    String? status,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Asset(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      syncStatus: syncStatus ?? this.syncStatus,
      assetCode: assetCode ?? this.assetCode,
      name: name ?? this.name,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      purchaseCostPaise: purchaseCostPaise ?? this.purchaseCostPaise,
      manufacturerModel: manufacturerModel ?? this.manufacturerModel,
      serialNumber: serialNumber ?? this.serialNumber,
      warrantyInformation: warrantyInformation ?? this.warrantyInformation,
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
      'asset_code': assetCode,
      'name': name,
      'purchase_date': purchaseDate?.toIso8601String(),
      'purchase_cost_paise': purchaseCostPaise,
      'manufacturer_model': manufacturerModel,
      'serial_number': serialNumber,
      'warranty_information': warrantyInformation,
      'status': status,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Asset.fromMap(Map<String, Object?> map) {
    return Asset(
      id: map['id'] as int?,
      uuid: map['uuid'] as String,
      syncStatus: map['sync_status'] as String? ?? syncStatusSynced,
      assetCode: map['asset_code'] as String,
      name: map['name'] as String,
      purchaseDate: map['purchase_date'] == null
          ? null
          : DateTime.parse(map['purchase_date'] as String),
      purchaseCostPaise: map['purchase_cost_paise'] as int?,
      manufacturerModel: map['manufacturer_model'] as String?,
      serialNumber: map['serial_number'] as String?,
      warrantyInformation: map['warranty_information'] as String?,
      status: map['status'] as String? ?? statusActive,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
