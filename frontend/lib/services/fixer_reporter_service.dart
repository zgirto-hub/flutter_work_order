import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/user.dart';
import 'user_service.dart';

class FixerReporterService {
  final _userService = UserService();
  String _errorDetail(http.Response res, String fallback) {
    try {
      final body = jsonDecode(res.body);
      return (body is Map ? body['detail'] : null) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<List<Map<String, dynamic>>> fetchFixerReporters() async {
    return fetchFixerDepartments();
  }

  Future<List<Map<String, dynamic>>> fetchFixerDepartments() async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/fixer-departments'),
    ).timeout(Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to fetch fixer departments'));
    }
    final data = jsonDecode(res.body);
    return List<Map<String, dynamic>>.from(data['fixer_departments'] ?? []);
  }

  Future<List<String>> getFixerDepartments(String fixerId) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/fixer-departments/user/$fixerId'),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return List<String>.from(data['departments'] ?? []);
    }
    return [];
  }

  Future<void> setFixerDepartments(String fixerId, List<String> departments) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/fixer-departments/bulk/$fixerId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'departments': departments}),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to update fixer departments'));
    }
  }

  Future<void> createFixerReporter({
    required String fixerDepartment,
    required List<String> reporterDepartments,
  }) async {
    await setFixerDepartments(fixerDepartment, reporterDepartments);
  }

  Future<void> updateFixerReporter({
    required String fixerDepartment,
    required List<String> reporterDepartments,
  }) async {
    await setFixerDepartments(fixerDepartment, reporterDepartments);
  }

  Future<void> deleteFixerReporter(String fixerDepartment) async {
    await removeFixerDepartment(fixerDepartment, '');
  }

  Future<void> addFixerDepartment(String fixerId, String department) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/fixer-departments'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fixer_id': fixerId,
        'department': department,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to add fixer department'));
    }
  }

  Future<void> removeFixerDepartment(String fixerId, String department) async {
    final res = await http.delete(
      Uri.parse('${AppConfig.baseUrl}/fixer-departments/$fixerId/${Uri.encodeComponent(department)}'),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to remove fixer department'));
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

  Future<List<AppUser>> fetchFixers() async {
    return _userService.fetchFixers();
  }
}
