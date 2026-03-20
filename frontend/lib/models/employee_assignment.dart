class EmployeeAssignment {
  final String id;
  final String fullName;
  final String? email;
  final String? department;
  final String? assignedAt;
  final String? assignedBy;

  const EmployeeAssignment({
    required this.id,
    required this.fullName,
    this.email,
    this.department,
    this.assignedAt,
    this.assignedBy,
  });

  factory EmployeeAssignment.fromJson(Map<String, dynamic> json) {
    final users = json['users'] as Map<String, dynamic>?;
    final fixerId = json['fixer_id'] ?? users?['id'] ?? '';
    
    return EmployeeAssignment(
      id: fixerId,
      fullName: users?['full_name'] ?? '',
      email: users?['email'],
      department: users?['department'],
      assignedAt: json['assigned_at']?.toString(),
      assignedBy: json['assigned_by'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fixer_id': id,
      'full_name': fullName,
      'email': email,
      'department': department,
    };
  }
}
