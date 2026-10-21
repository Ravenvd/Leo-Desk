import 'package:uuid/uuid.dart';

/// Stock categories supported by Leo Desk's consumables inventory.
class Consumable {
  static const String categoryEmbroideryThread = 'Embroidery thread';
  static const String categoryAariThread = 'Aari thread';
  static const String categoryBobbinThread = 'Bobbin thread';
  static const String categoryBeads = 'Beads';
  static const String categorySequins = 'Sequins';
  static const String categoryStabilizers = 'Stabilizers';
  static const String categoryOils = 'Oils';
  static const String categoryTailorsChalk = "Tailor's chalk";

  static const List<String> categories = [
    categoryEmbroideryThread,
    categoryAariThread,
    categoryBobbinThread,
    categoryBeads,
    categorySequins,
    categoryStabilizers,
    categoryOils,
    categoryTailorsChalk,
  ];

  static const String trackingPercentage = 'percentage';
  static const String trackingQuantity = 'quantity';
  static const String trackingCount = 'count';

  static const String unitMetres = 'm';
  static const String unitGrams = 'g';
  static const String unitCount = 'count';
  static const String unitMillilitres = 'ml';

  static const String syncStatusPending = 'pending';
  static const String syncStatusSynced = 'synced';

  final int? id;
  final String uuid;
  final String syncStatus;
  final String category;
  final String name;
  final String? size;
  final String? finish;
  final String? colour;
  final String trackingType;
  final String stockUnit;
  final double reorderLevel;
  final double? defaultPackQuantity;
  final DateTime createdAt;
  final DateTime updatedAt;

  Consumable({
    this.id,
    String? uuid,
    this.syncStatus = syncStatusPending,
    required this.category,
    required this.name,
    this.size,
    this.finish,
    this.colour,
    required this.trackingType,
    required this.stockUnit,
    this.reorderLevel = 0,
    this.defaultPackQuantity,
    required this.createdAt,
    required this.updatedAt,
  }) : uuid = uuid ?? const Uuid().v4() {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Must not be empty.');
    }
    if (reorderLevel < 0) {
      throw ArgumentError.value(reorderLevel, 'reorderLevel', 'Must be >= 0.');
    }
    if (defaultPackQuantity != null && defaultPackQuantity! <= 0) {
      throw ArgumentError.value(
        defaultPackQuantity,
        'defaultPackQuantity',
        'Must be > 0 when provided.',
      );
    }
  }

  Consumable copyWith({
    int? id,
    String? uuid,
    String? syncStatus,
    String? category,
    String? name,
    String? size,
    String? finish,
    String? colour,
    String? trackingType,
    String? stockUnit,
    double? reorderLevel,
    double? defaultPackQuantity,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Consumable(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      syncStatus: syncStatus ?? this.syncStatus,
      category: category ?? this.category,
      name: name ?? this.name,
      size: size ?? this.size,
      finish: finish ?? this.finish,
      colour: colour ?? this.colour,
      trackingType: trackingType ?? this.trackingType,
      stockUnit: stockUnit ?? this.stockUnit,
      reorderLevel: reorderLevel ?? this.reorderLevel,
      defaultPackQuantity: defaultPackQuantity ?? this.defaultPackQuantity,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'uuid': uuid,
        'sync_status': syncStatus,
        'category': category,
        'name': name,
        'size': size,
        'finish': finish,
        'colour': colour,
        'tracking_type': trackingType,
        'stock_unit': stockUnit,
        'reorder_level': reorderLevel,
        'default_pack_quantity': defaultPackQuantity,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Consumable.fromMap(Map<String, Object?> map) => Consumable(
        id: map['id'] as int?,
        uuid: map['uuid'] as String,
        syncStatus: map['sync_status'] as String? ?? syncStatusSynced,
        category: map['category'] as String,
        name: map['name'] as String,
        size: map['size'] as String?,
        finish: map['finish'] as String?,
        colour: map['colour'] as String?,
        trackingType: map['tracking_type'] as String,
        stockUnit: map['stock_unit'] as String,
        reorderLevel: (map['reorder_level'] as num?)?.toDouble() ?? 0,
        defaultPackQuantity:
            (map['default_pack_quantity'] as num?)?.toDouble(),
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  /// Human-facing quantity for mass-tracked supplies stored internally in g.
  double displayQuantity(double stockQuantity) =>
      stockUnit == unitGrams ? stockQuantity / 1000 : stockQuantity;

  String get displayUnit => stockUnit == unitGrams
      ? 'kg'
      : stockUnit == unitMillilitres
          ? 'ml'
          : stockUnit == unitMetres
              ? 'm'
              : 'pcs';
}
