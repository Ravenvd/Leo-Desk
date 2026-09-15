import 'package:uuid/uuid.dart';

class Expense {
  static const List<String> categories = [
    'Raw Materials',
    'Salaries',
    'Miscellaneous',
    'Fixed Expenses',
  ];

  final int? id;
  final String uuid;
  final String syncStatus;
  final DateTime expenseDate;
  final String category;
  final String description;
  final int amountPaise;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Expense({
    this.id,
    String? uuid,
    this.syncStatus = 'pending',
    required this.expenseDate,
    required this.category,
    required this.description,
    required this.amountPaise,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  }) : uuid = uuid ?? const Uuid().v4();

  Expense copyWith({
    int? id,
    String? uuid,
    String? syncStatus,
    DateTime? expenseDate,
    String? category,
    String? description,
    int? amountPaise,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Expense(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      syncStatus: syncStatus ?? this.syncStatus,
      expenseDate: expenseDate ?? this.expenseDate,
      category: category ?? this.category,
      description: description ?? this.description,
      amountPaise: amountPaise ?? this.amountPaise,
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
      'expense_date': expenseDate.toIso8601String(),
      'category': category,
      'description': description,
      'amount_paise': amountPaise,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Expense.fromMap(Map<String, Object?> map) {
    return Expense(
      id: map['id'] as int?,
      uuid: map['uuid'] as String,
      syncStatus: map['sync_status'] as String? ?? 'synced',
      expenseDate: DateTime.parse(map['expense_date'] as String),
      category: map['category'] as String,
      description: map['description'] as String,
      amountPaise: map['amount_paise'] as int,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
