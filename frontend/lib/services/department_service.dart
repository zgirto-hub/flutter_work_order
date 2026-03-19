import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class DepartmentService {
  String _errorDetail(http.Response res, String fallback) {
    try {
      final body = jsonDecode(res.body);
      return (body is Map ? body['detail'] : null) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<List<String>> fetchDepartments() async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/departments'),
    ).timeout(Duration(seconds: 10));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return List<String>.from(data['departments'] ?? []);
    }
    throw Exception(_errorDetail(res, 'Failed to fetch departments'));
  }

  Future<Map<String, dynamic>> fetchDepartmentInfo(String departmentName) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/departments/${Uri.encodeComponent(departmentName)}'),
    ).timeout(Duration(seconds: 10));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data;
    }
    throw Exception(_errorDetail(res, 'Failed to fetch department info'));
  }

  Future<int> getUserCount(String departmentName) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/departments/${Uri.encodeComponent(departmentName)}/user-count'),
    ).timeout(Duration(seconds: 10));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data['user_count'] ?? 0;
    }
    return 0;
  }

  Future<void> createDepartment(String name) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/departments'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name}),
    ).timeout(Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to create department'));
    }
  }

  Future<void> renameDepartment(String oldName, String newName) async {
    final res = await http.patch(
      Uri.parse('${AppConfig.baseUrl}/departments/${Uri.encodeComponent(oldName)}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'new_name': newName}),
    ).timeout(Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to rename department'));
    }
  }

  Future<void> deleteDepartment(String name) async {
    final res = await http.delete(
      Uri.parse('${AppConfig.baseUrl}/departments/${Uri.encodeComponent(name)}'),
    ).timeout(Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to delete department'));
    }
  }
}
