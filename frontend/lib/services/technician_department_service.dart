import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/user.dart';
import 'user_service.dart';

class TechnicianDepartmentService {
  final _userService = UserService();
  String _errorDetail(http.Response res, String fallback) {
    try {
      final body = jsonDecode(res.body);
      return (body is Map ? body['detail'] : null) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<List<Map<String, dynamic>>> fetchTechnicianDepartments() async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/technician-departments'),
    ).timeout(Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to fetch technician departments'));
    }
    final data = jsonDecode(res.body);
    return List<Map<String, dynamic>>.from(data['technician_departments'] ?? []);
  }

  Future<List<String>> getTechnicianDepartments(String technicianId) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/technician-departments/user/$technicianId'),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return List<String>.from(data['departments'] ?? []);
    }
    return [];
  }

  Future<void> setTechnicianDepartments(String technicianId, List<String> departments) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/technician-departments/bulk/$technicianId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'departments': departments}),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to update technician departments'));
    }
  }

  Future<void> addTechnicianDepartment(String technicianId, String department) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/technician-departments'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'technician_id': technicianId,
        'department': department,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to add technician department'));
    }
  }

  Future<void> removeTechnicianDepartment(String technicianId, String department) async {
    final res = await http.delete(
      Uri.parse('${AppConfig.baseUrl}/technician-departments/$technicianId/${Uri.encodeComponent(department)}'),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to remove technician department'));
    }
  }

  Future<List<String>> fetchAllDepartments() async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/departments/all'),
    ).timeout(Duration(seconds: 10));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return List<String>.from(data['departments'] ?? []);
    }
    return [];
  }

  Future<List<String>> fetchDepartments() async {
    return fetchAllDepartments();
  }

  Future<List<AppUser>> fetchTechnicians() async {
    return _userService.fetchTechnicians();
  }
}
