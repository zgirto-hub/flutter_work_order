class EmployeeAssignment {
  final String id;
  final String fullName;
  final String? email;
  final String? department;

  const EmployeeAssignment({
    required this.id,
    required this.fullName,
    this.email,
    this.department,
  });

  factory EmployeeAssignment.fromJson(Map<String, dynamic> json) {
    final users = json['users'] as Map<String, dynamic>?;
    return EmployeeAssignment(
      id: users?['id'] ?? json['user_id'] ?? '',
      fullName: users?['full_name'] ?? '',
      email: users?['email'],
      department: users?['department'],
    );
  }
}
