import 'package:uuid/uuid.dart';

class Customer {
  final int? id;
  final String uuid;
  final String syncStatus;
  final String name;
  final String? phone;
  final String? whatsapp;
  final String? email;
  final String? address;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Customer({
    this.id,
    String? uuid,
    this.syncStatus = 'pending',
    required this.name,
    this.phone,
    this.whatsapp,
    this.email,
    this.address,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  }) : uuid = uuid ?? Uuid().v4();

  Customer copyWith({
    int? id,
    String? uuid,
    String? syncStatus,
    String? name,
    String? phone,
    String? whatsapp,
    String? email,
    String? address,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Customer(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      syncStatus: syncStatus ?? this.syncStatus,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      whatsapp: whatsapp ?? this.whatsapp,
      email: email ?? this.email,
      address: address ?? this.address,
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
      'name': name,
      'phone': phone,
      'whatsapp': whatsapp,
      'email': email,
      'address': address,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Customer.fromMap(Map<String, Object?> map) {
    return Customer(
      id: map['id'] as int?,
      // Some pre-v12/intermediate databases may contain a NULL UUID.
      // Generate a stable new UUID rather than crashing while loading the
      // customer. Normal v12+ rows always provide a persisted UUID.
      uuid: map['uuid'] as String? ?? Uuid().v4(),
      syncStatus: map['sync_status'] as String? ?? 'synced',
      name: map['name'] as String,
      phone: map['phone'] as String?,
      whatsapp: map['whatsapp'] as String?,
      email: map['email'] as String?,
      address: map['address'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
