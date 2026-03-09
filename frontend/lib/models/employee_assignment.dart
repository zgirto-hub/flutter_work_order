class EmployeeAssignment {
  final String id;
  final String fullName;

  const EmployeeAssignment({
    required this.id,
    required this.fullName,
  });

  factory EmployeeAssignment.fromJson(Map<String, dynamic> json) {
    return EmployeeAssignment(
      id: json['employees']?['id'] ?? '',
      fullName: json['employees']?['full_name'] ?? '',
    );
  }
}
