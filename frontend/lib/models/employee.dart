class Employee {
  final String id;
  final String fullName;
  final String shiftType;
  final bool active;
  final String? profileId;
  final String department;
  final String? mobile;
  final String? location;
  final String userType;

  const Employee({
    required this.id,
    required this.fullName,
    required this.shiftType,
    required this.active,
    this.profileId,
    this.department = 'General',
    this.mobile,
    this.location,
    this.userType = 'tech',
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'],
      fullName: json['full_name'] ?? '',
      shiftType: json['shift_type'] ?? '',
      active: json['active'] ?? true,
      profileId: json['profile_id'],
      department: json['department'] ?? 'General',
      mobile: json['mobile'],
      location: json['location'],
      userType: json['user_type'] ?? 'tech',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'shift_type': shiftType,
      'active': active,
      'profile_id': profileId,
      'department': department,
      'mobile': mobile,
      'location': location,
      'user_type': userType,
    };
  }
}
