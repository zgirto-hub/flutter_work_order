class Employee {
  final String id;
  final String fullName;
  final String shiftType;
  final bool active;
  final String? profileId;

  const Employee({
    required this.id,
    required this.fullName,
    required this.shiftType,
    required this.active,
    this.profileId,
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'],
      fullName: json['full_name'] ?? '',
      shiftType: json['shift_type'] ?? '',
      active: json['active'] ?? true,
      profileId: json['profile_id'],
    );
  }
}
