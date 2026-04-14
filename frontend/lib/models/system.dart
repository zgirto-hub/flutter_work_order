class System {
  final String id;
  final String name;
  final String? category;
  final int sortOrder;
  final bool isActive;
  final bool needsReview;
  final DateTime createdAt;
  final DateTime updatedAt;

  System({
    required this.id,
    required this.name,
    this.category,
    required this.sortOrder,
    required this.isActive,
    required this.needsReview,
    required this.createdAt,
    required this.updatedAt,
  });

  factory System.fromJson(Map<String, dynamic> json) {
    return System(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String?,
      sortOrder: json['sort_order'] as int,
      isActive: json['is_active'] as bool,
      needsReview: json['needs_review'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'category': category,
      'sort_order': sortOrder,
    };
  }

  System copyWith({
    String? id,
    String? name,
    String? category,
    int? sortOrder,
    bool? isActive,
    bool? needsReview,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return System(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      needsReview: needsReview ?? this.needsReview,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
