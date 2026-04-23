import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/department.dart';
import '../config.dart';

class DepartmentService {
  /// Fetch all active departments
  Future<List<Department>> fetchDepartments({bool? isActive}) async {
    final params = <String, String>{};
    if (isActive != null) {
      params['is_active'] = isActive.toString();
    }

    final uri = Uri.parse('${AppConfig.baseUrl}/departments')
        .replace(queryParameters: params.isEmpty ? null : params);

    final res = await http.get(uri);
    
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch departments');
    }

    final data = jsonDecode(res.body);
    return (data['departments'] as List)
        .map((j) => Department.fromJson(j))
        .toList();
  }

  /// Fetch departments with user and WO counts in a single request
  Future<List<Map<String, dynamic>>> fetchDepartmentsWithCounts({bool? isActive}) async {
    final params = <String, String>{};
    if (isActive != null) {
      params['is_active'] = isActive.toString();
    }

    final uri = Uri.parse('${AppConfig.baseUrl}/departments/with-counts')
        .replace(queryParameters: params.isEmpty ? null : params);

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch departments');
    }

    final data = jsonDecode(res.body);
    return List<Map<String, dynamic>>.from(data['departments'] ?? []);
  }

  /// Fetch a single department by ID
  Future<Department?> fetchDepartmentById(String id) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/departments/$id'),
    );

    if (res.statusCode != 200) {
      return null;
    }

    final data = jsonDecode(res.body);
    final dept = data['department'];
    if (dept is! Map<String, dynamic>) return null;
    return Department.fromJson(dept);
  }

  /// Create a new department
  Future<Department> createDepartment(String name) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/departments'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name}),
    );

    if (res.statusCode != 200) {
      final error = jsonDecode(res.body);
      throw Exception(error['detail'] ?? 'Failed to create department');
    }

    final data = jsonDecode(res.body);
    final departmentId = data['department_id'];
    
    // Fetch the full department object
    final department = await fetchDepartmentById(departmentId);
    if (department == null) {
      throw Exception('Failed to fetch created department');
    }
    return department;
  }

  /// Update a department (name and/or active status)
  Future<void> updateDepartment(String departmentId, {
    required String name,
    bool? isActive,
  }) async {
    final res = await http.patch(
      Uri.parse('${AppConfig.baseUrl}/departments/$departmentId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        if (isActive != null) 'is_active': isActive,
      }),
    );

    if (res.statusCode != 200) {
      final error = jsonDecode(res.body);
      throw Exception(error['detail'] ?? 'Failed to update department');
    }
  }

  /// Delete a department (soft delete)
  Future<void> deleteDepartment(String departmentId) async {
    final res = await http.delete(
      Uri.parse('${AppConfig.baseUrl}/departments/$departmentId'),
    );

    if (res.statusCode != 200) {
      final error = jsonDecode(res.body);
      throw Exception(error['detail'] ?? 'Failed to delete department');
    }
  }

  /// Get technician count for a department
  Future<int> getTechnicianCount(String departmentId) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/departments/$departmentId/technician-count'),
    );

    if (res.statusCode != 200) {
      return 0;
    }

    final data = jsonDecode(res.body);
    return data['technician_count'] ?? 0;
  }

  /// Get work order count for a department
  Future<int> getWorkOrderCount(String departmentId) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/departments/$departmentId/work-order-count'),
    );

    if (res.statusCode != 200) {
      return 0;
    }

    final data = jsonDecode(res.body);
    return data['work_order_count'] ?? 0;
  }

  /// Fetch current user's departments and global viewer status
  Future<({List<Department> departments, bool isGlobalViewer})> fetchMyDepartments() async {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? '';

    final uri = Uri.parse('${AppConfig.baseUrl}/departments/mine?user_email=${Uri.encodeComponent(email)}');
    final res = await http.get(uri);

    if (res.statusCode != 200) {
      throw Exception('Failed to fetch my departments');
    }

    final data = jsonDecode(res.body);
    final depts = (data['departments'] as List)
        .map((j) => Department.fromJson(j as Map<String, dynamic>))
        .toList();
    final isGlobalViewer = data['is_global_viewer'] as bool? ?? false;

    return (departments: depts, isGlobalViewer: isGlobalViewer);
  }
}
