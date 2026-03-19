import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class DepartmentService {
  Future<List<Map<String, dynamic>>> getDepartments() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/departments'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['departments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>?> createDepartment(String name) async {
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/departments'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['department'];
      } else {
        final error = jsonDecode(res.body);
        throw Exception(error['detail'] ?? 'Failed to create department');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> updateDepartment(String id, String name) async {
    try {
      final res = await http.patch(
        Uri.parse('${AppConfig.baseUrl}/departments/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['department'];
      } else {
        final error = jsonDecode(res.body);
        throw Exception(error['detail'] ?? 'Failed to update department');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteDepartment(String id) async {
    try {
      final res = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/departments/$id'),
      );
      if (res.statusCode != 200) {
        final error = jsonDecode(res.body);
        throw Exception(error['detail'] ?? 'Failed to delete department');
      }
    } catch (e) {
      rethrow;
    }
  }
}
