enum UserType { admin, technician, reporter }

class AppUser {
  final String id;
  final String? authId;
  final String email;
  final String? fullName;
  final String? mobile;
  final String? location;
  final String? departmentId;
  final UserType userType;
  final bool isActive;
  final String createdAt;
  final List<String> departments;
  final List<Map<String, String>>
      technicianDepartments; // [{id, name}] from /users/me
  final List<String>?
      allowedScreens; // null = no restrictions, list = only these screens
  final bool isSupervisor;
  final bool isSuperintendent;
  final int? approvalLevel;

  const AppUser({
    required this.id,
    this.authId,
    required this.email,
    this.fullName,
    this.mobile,
    this.location,
    this.departmentId,
    required this.userType,
    this.isActive = true,
    this.createdAt = '',
    this.departments = const [],
    this.technicianDepartments = const [],
    this.allowedScreens,
    this.isSupervisor = false,
    this.isSuperintendent = false,
    this.approvalLevel,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] ?? '',
      authId: json['auth_id'],
      email: json['email'] ?? '',
      fullName: json['full_name'],
      mobile: json['mobile'],
      location: json['location'],
      departmentId: json['department_id'],
      userType: _parseUserType(json['user_type']),
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] ?? '',
      departments: (json['departments'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
      technicianDepartments:
          (json['technician_departments'] as List<dynamic>? ?? [])
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v.toString())))
              .toList(),
      allowedScreens: json['allowed_screens'] is List
          ? (json['allowed_screens'] as List)
              .map((e) => e.toString())
              .toList()
          : null,
      isSupervisor: json['is_supervisor'] ?? false,
      isSuperintendent: json['is_superintendent'] ?? false,
      approvalLevel: json['approval_level'],
    );
  }

  factory AppUser.fromEmployeesJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] ?? '',
      authId: json['profile_id'],
      email: json['email'] ?? '',
      fullName: json['full_name'] ?? '',
      mobile: json['mobile'],
      location: json['location'],
      departmentId: json['department_id'],
      userType: _parseUserType(json['user_type'] ?? 'reporter'),
      isActive: true,
      createdAt: json['created_at'] ?? '',
    );
  }

  static UserType _parseUserType(String? type) {
    switch (type?.toLowerCase()) {
      case 'admin':
        return UserType.admin;
      case 'technician':
        return UserType.technician;
      case 'reporter':
      default:
        return UserType.reporter;
    }
  }

  String get userTypeString {
    switch (userType) {
      case UserType.admin:
        return 'admin';
      case UserType.technician:
        return 'technician';
      case UserType.reporter:
        return 'reporter';
    }
  }

  String get displayName =>
      fullName?.isNotEmpty == true ? fullName! : email.split('@').first;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'auth_id': authId,
      'email': email,
      'full_name': fullName,
      'mobile': mobile,
      'location': location,
      'department_id': departmentId,
      'user_type': userTypeString,
      'is_active': isActive,
      'is_supervisor': isSupervisor,
      'is_superintendent': isSuperintendent,
      'approval_level': approvalLevel,
    };
  }

  AppUser copyWith({
    String? id,
    String? authId,
    String? email,
    String? fullName,
    String? mobile,
    String? location,
    String? departmentId,
    UserType? userType,
    bool? isActive,
    String? createdAt,
    List<String>? departments,
    List<String>? allowedScreens,
    bool? isSupervisor,
    bool? isSuperintendent,
    int? approvalLevel,
  }) {
    return AppUser(
      id: id ?? this.id,
      authId: authId ?? this.authId,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      mobile: mobile ?? this.mobile,
      location: location ?? this.location,
      departmentId: departmentId ?? this.departmentId,
      userType: userType ?? this.userType,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      departments: departments ?? this.departments,
      allowedScreens: allowedScreens ?? this.allowedScreens,
      isSupervisor: isSupervisor ?? this.isSupervisor,
      isSuperintendent: isSuperintendent ?? this.isSuperintendent,
      approvalLevel: approvalLevel ?? this.approvalLevel,
    );
  }
}
