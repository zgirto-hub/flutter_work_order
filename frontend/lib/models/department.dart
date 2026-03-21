class Department {
  final String id;
  final String name;
  final bool isActive;
  final String? createdAt;

  const Department({
    required this.id,
    required this.name,
    this.isActive = true,
    this.createdAt,
  });

  factory Department.fromJson(Map<String, dynamic> json) {
    return Department(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'is_active': isActive,
    };
  }

  @override
  String toString() => name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Department &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
