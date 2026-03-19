class AppUser {
  final String id;
  final String? authId;
  final String email;
  final String? fullName;
  final String? mobile;
  final String? location;
  final String userType;
  final String? department;
  final bool isActive;
  final DateTime? createdAt;

  const AppUser({
    required this.id,
    this.authId,
    required this.email,
    this.fullName,
    this.mobile,
    this.location,
    this.userType = 'reporter',
    this.department,
    this.isActive = true,
    this.createdAt,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] ?? '',
      authId: json['auth_id'],
      email: json['email'] ?? '',
      fullName: json['full_name'],
      mobile: json['mobile'],
      location: json['location'],
      userType: json['user_type'] ?? 'reporter',
      department: json['department'],
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'auth_id': authId,
      'email': email,
      'full_name': fullName,
      'mobile': mobile,
      'location': location,
      'user_type': userType,
      'department': department,
      'is_active': isActive,
    };
  }

  AppUser copyWith({
    String? id,
    String? authId,
    String? email,
    String? fullName,
    String? mobile,
    String? location,
    String? userType,
    String? department,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return AppUser(
      id: id ?? this.id,
      authId: authId ?? this.authId,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      mobile: mobile ?? this.mobile,
      location: location ?? this.location,
      userType: userType ?? this.userType,
      department: department ?? this.department,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
