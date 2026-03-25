import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/department.dart';

class DepartmentRouteService {
  String _errorDetail(http.Response res, String fallback) {
    try {
      final body = jsonDecode(res.body);
      return (body is Map ? body['detail'] : null) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  /// Get all routing rules (for admin screen)
  Future<List<Map<String, dynamic>>> fetchAllRoutes() async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/department-routes'),
    ).timeout(Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to fetch department routes'));
    }
    final data = jsonDecode(res.body);
    return List<Map<String, dynamic>>.from(data['department_routes'] ?? []);
  }

  /// Get allowed target departments for a given source department
  Future<List<Department>> fetchTargetDepartments(String sourceDepartmentId) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/department-routes/source/$sourceDepartmentId'),
    ).timeout(Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to fetch target departments'));
    }
    final data = jsonDecode(res.body);
    return (data['target_departments'] as List)
        .map((j) => Department.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Set all target departments for a source (bulk replace)
  Future<void> setTargetDepartments(String sourceDepartmentId, List<String> targetDepartmentIds) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/department-routes/bulk/$sourceDepartmentId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'target_department_ids': targetDepartmentIds}),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to update department routes'));
    }
  }

  /// Add a single route
  Future<void> addRoute(String sourceDepartmentId, String targetDepartmentId) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/department-routes'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'source_department_id': sourceDepartmentId,
        'target_department_id': targetDepartmentId,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to add department route'));
    }
  }

  /// Remove a single route
  Future<void> removeRoute(String sourceDepartmentId, String targetDepartmentId) async {
    final res = await http.delete(
      Uri.parse('${AppConfig.baseUrl}/department-routes/$sourceDepartmentId/$targetDepartmentId'),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to remove department route'));
    }
  }
}
