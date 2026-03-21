import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart';
import '../config.dart';

class UserService {
  String get _email => Supabase.instance.client.auth.currentUser?.email ?? '';

  String _errorDetail(http.Response res, String fallback) {
    try {
      final body = jsonDecode(res.body);
      return (body is Map ? body['detail'] : null) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<List<AppUser>> fetchUsers() async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/users'),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to fetch users'));
    }
    final data = jsonDecode(res.body);
    return (data['users'] as List)
        .map((j) => AppUser.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<AppUser?> fetchUser(String userId) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/users/$userId'),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return AppUser.fromJson(data['user'] as Map<String, dynamic>);
    }
    return null;
  }

  Future<AppUser?> fetchCurrentUser() async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/users/me?email=${Uri.encodeComponent(_email)}'),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      if (data['user'] != null) {
        return AppUser.fromJson(data['user'] as Map<String, dynamic>);
      }
    }
    return null;
  }

  Future<String?> createUser({
    required String email,
    required String password,
    required String userType,
    required String fullName,
    String? mobile,
    String? location,
    String? departmentId,
  }) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/users?admin_email=${Uri.encodeComponent(_email)}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'user_type': userType,
        'full_name': fullName,
        'mobile': mobile ?? '',
        'location': location ?? '',
        if (departmentId != null) 'department_id': departmentId,
      }),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data['user']?['id'];
    }
    throw Exception(_errorDetail(res, 'Failed to create user'));
  }

  Future<void> updateUser({
    required String userId,
    String? fullName,
    String? mobile,
    String? location,
    String? departmentId,
  }) async {
    final body = <String, dynamic>{};
    if (fullName != null) body['full_name'] = fullName;
    if (mobile != null) body['mobile'] = mobile;
    if (location != null) body['location'] = location;
    if (departmentId != null) body['department_id'] = departmentId;

    final res = await http.patch(
      Uri.parse('${AppConfig.baseUrl}/users/$userId?admin_email=${Uri.encodeComponent(_email)}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to update user'));
    }
  }

  Future<void> changeUserRole({
    required String userId,
    required String userType,
  }) async {
    final res = await http.patch(
      Uri.parse('${AppConfig.baseUrl}/users/$userId/role?admin_email=${Uri.encodeComponent(_email)}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_type': userType}),
    );

    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to change user role'));
    }
  }

  Future<void> deactivateUser(String userId) async {
    final res = await http.patch(
      Uri.parse('${AppConfig.baseUrl}/users/$userId/deactivate?admin_email=${Uri.encodeComponent(_email)}'),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to deactivate user'));
    }
  }

  Future<void> activateUser(String userId) async {
    final res = await http.patch(
      Uri.parse('${AppConfig.baseUrl}/users/$userId/activate?admin_email=${Uri.encodeComponent(_email)}'),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to activate user'));
    }
  }

  Future<String> getUserRole() async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/user-role?email=${Uri.encodeComponent(_email)}'),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return (data['user_type'] ?? 'reporter').toString().toLowerCase();
    }
    return 'reporter';
  }

  Future<List<String>> getTechnicianDepartments(String userId) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/technician-departments/user/$userId'),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return List<String>.from(data['departments'] ?? []);
    }
    return [];
  }

  Future<void> setTechnicianDepartments(String userId, List<String> departments) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/technician-departments/bulk/$userId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'departments': departments}),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to update technician departments'));
    }
  }

  Future<List<AppUser>> fetchTechnicians() async {
    final users = await fetchUsers();
    return users.where((u) => (u.userType == UserType.technician || u.userType == UserType.admin) && u.isActive).toList();
  }

  Future<List<String>> fetchDepartments() async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/departments/all'),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return List<String>.from(data['departments'] ?? []);
    }
    return [
      'Operations',
      'ATC',
      'Finance',
      'NOTAM',
      'MET',
      'IT-Support',
      'Helpdesk',
      'General',
    ];
  }
}
