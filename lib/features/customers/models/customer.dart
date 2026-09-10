import 'package:uuid/uuid.dart';

class Customer {
  final int? id;
  final String uuid;
  final String name;
  final String? phone;
  final String? whatsapp;
  final String? email;
  final String? address;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String customerType;
  final String serviceRequired;

  Customer({
    this.id,
    String? uuid,
    required this.name,
    this.phone,
    this.whatsapp,
    this.email,
    this.address,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.customerType,
    required this.serviceRequired,
  }) : uuid = uuid ?? Uuid().v4();

  Customer copyWith({
    int? id,
    String? uuid,
    String? name,
    String? phone,
    String? whatsapp,
    String? email,
    String? address,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? customerType,
    String? serviceRequired,
  }) {
    return Customer(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      whatsapp: whatsapp ?? this.whatsapp,
      email: email ?? this.email,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      customerType: customerType ?? this.customerType,
      serviceRequired: serviceRequired ?? this.serviceRequired,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'uuid' : uuid, 
      'name': name,
      'phone': phone,
      'whatsapp': whatsapp,
      'email': email,
      'address': address,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'customer_type': customerType,
      'service_required': serviceRequired,
    };
  }

  factory Customer.fromMap(Map<String, Object?> map) {
    return Customer(
      id: map['id'] as int?,
      uuid: map['uuid'] as String, 
      name: map['name'] as String,
      phone: map['phone'] as String?,
      whatsapp: map['whatsapp'] as String?,
      email: map['email'] as String?,
      address: map['address'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      customerType: map['customer_type'] as String,
      serviceRequired: map['service_required'] as String,
    );
  }
}