import 'dart:convert';
import 'package:http/http.dart' as http;
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
}
