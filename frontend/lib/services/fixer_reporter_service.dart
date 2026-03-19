import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class FixerReporterService {
  String _errorDetail(http.Response res, String fallback) {
    try {
      final body = jsonDecode(res.body);
      return (body is Map ? body['detail'] : null) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<List<Map<String, dynamic>>> fetchFixerReporters() async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/fixer-reporters'),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to fetch fixer reporters'));
    }
    final data = jsonDecode(res.body);
    return List<Map<String, dynamic>>.from(data['fixer_reporters'] ?? []);
  }

  Future<Map<String, dynamic>?> fetchFixerReporter(String fixerDepartment) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/fixer-reporters/${Uri.encodeComponent(fixerDepartment)}'),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data['fixer_reporter'];
    }
    return null;
  }

  Future<void> createFixerReporter({
    required String fixerDepartment,
    required List<String> reporterDepartments,
  }) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/fixer-reporters'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fixer_department': fixerDepartment,
        'reporter_departments': reporterDepartments,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to create fixer reporter'));
    }
  }

  Future<void> updateFixerReporter({
    required String fixerDepartment,
    required List<String> reporterDepartments,
  }) async {
    final res = await http.patch(
      Uri.parse('${AppConfig.baseUrl}/fixer-reporters/${Uri.encodeComponent(fixerDepartment)}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'reporter_departments': reporterDepartments,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to update fixer reporter'));
    }
  }

  Future<void> deleteFixerReporter(String fixerDepartment) async {
    final res = await http.delete(
      Uri.parse('${AppConfig.baseUrl}/fixer-reporters/${Uri.encodeComponent(fixerDepartment)}'),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to delete fixer reporter'));
    }
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

  Future<List<String>> fetchFixerDepartments() async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/fixer-departments'),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return List<String>.from(data['fixer_departments'] ?? []);
    }
    return [];
  }
}
