import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/app_user.dart';
import '../config.dart';

class UserService {
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
        .map((j) => AppUser.fromJson(j))
        .toList();
  }

  Future<AppUser?> fetchUser(String userId) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/users/$userId'),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return AppUser.fromJson(data['user']);
    }
    return null;
  }

  Future<AppUser?> fetchCurrentUser(String email) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/users/me?email=${Uri.encodeComponent(email)}'),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      if (data['user'] != null) {
        return AppUser.fromJson(data['user']);
      }
    }
    return null;
  }

  Future<String?> createUser({
    required String email,
    required String password,
    required String userType,
    required String fullName,
    String? department,
    String? mobile,
    String? location,
  }) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/users'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'user_type': userType,
        'full_name': fullName,
        'department': department,
        'mobile': mobile ?? '',
        'location': location ?? '',
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
    String? department,
    String? mobile,
    String? location,
  }) async {
    final body = <String, dynamic>{};
    if (fullName != null) body['full_name'] = fullName;
    if (department != null) body['department'] = department;
    if (mobile != null) body['mobile'] = mobile;
    if (location != null) body['location'] = location;

    final res = await http.patch(
      Uri.parse('${AppConfig.baseUrl}/users/$userId'),
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
    String? department,
  }) async {
    final body = <String, dynamic>{'user_type': userType};
    if (department != null) body['department'] = department;

    final res = await http.patch(
      Uri.parse('${AppConfig.baseUrl}/users/$userId/role'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to change user role'));
    }
  }

  Future<void> deactivateUser(String userId) async {
    final res = await http.patch(
      Uri.parse('${AppConfig.baseUrl}/users/$userId/deactivate'),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to deactivate user'));
    }
  }

  Future<void> activateUser(String userId) async {
    final res = await http.patch(
      Uri.parse('${AppConfig.baseUrl}/users/$userId/activate'),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to activate user'));
    }
  }

  Future<String?> register({
    required String email,
    required String password,
    required String fullName,
    required String department,
    required String mobile,
    required String location,
  }) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'full_name': fullName,
        'department': department,
        'mobile': mobile,
        'location': location,
      }),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data['email'];
    }
    throw Exception(_errorDetail(res, 'Failed to register'));
  }

  Future<String> getUserRole(String email) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/user-role?email=${Uri.encodeComponent(email)}'),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data['user_type'] ?? 'reporter';
    }
    return 'reporter';
  }

  Future<List<String>> fetchDepartments() async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/departments'),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return List<String>.from(data['departments'] ?? []);
    }
    return [];
  }
}
