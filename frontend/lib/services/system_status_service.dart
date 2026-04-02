import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/system_status_report.dart';
import '../config.dart';

class SystemStatusService {
  Future<List<SystemStatus>> fetchTodayStatus({String? date}) async {
    final params = <String, String>{};
    if (date != null) params['target_date'] = date;

    final uri = Uri.parse('${AppConfig.baseUrl}/system-status/today')
        .replace(queryParameters: params.isEmpty ? null : params);

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch system status');
    }

    final data = jsonDecode(res.body);
    return (data['systems'] as List)
        .map((j) => SystemStatus.fromJson(j))
        .toList();
  }

  Future<List<SystemStatusReport>> fetchHistory({
    String? systemName,
    int limit = 50,
  }) async {
    final params = <String, String>{'limit': limit.toString()};
    if (systemName != null) params['system_name'] = systemName;

    final uri = Uri.parse('${AppConfig.baseUrl}/system-status/history')
        .replace(queryParameters: params);

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch history');
    }

    final data = jsonDecode(res.body);
    return (data['reports'] as List)
        .map((j) => SystemStatusReport.fromJson(j))
        .toList();
  }

  Future<SystemStatusReport> reportIssue({
    required String systemName,
    required String reportDate,
    required String notes,
    required String reportedBy,
    required String reportedByName,
  }) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/system-status/report'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'system_name': systemName,
        'report_date': reportDate,
        'notes': notes,
        'reported_by': reportedBy,
        'reported_by_name': reportedByName,
      }),
    );

    if (res.statusCode == 409) {
      throw Exception(
          'An unresolved issue already exists for this system on this date');
    }
    if (res.statusCode != 200) {
      throw Exception('Failed to report issue');
    }

    final data = jsonDecode(res.body);
    return SystemStatusReport.fromJson(data['report']);
  }

  Future<void> resolveIssue({
    required String reportId,
    required String resolvedBy,
    String resolvedNotes = '',
    String? resolvedAt,
  }) async {
    final res = await http.patch(
      Uri.parse('${AppConfig.baseUrl}/system-status/$reportId/resolve'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'resolved_by': resolvedBy,
        'resolved_notes': resolvedNotes,
        if (resolvedAt != null) 'resolved_at': resolvedAt,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to resolve issue');
    }
  }

  Future<SystemStatusReport> updateIssue({
    required String reportId,
    String? notes,
    String? reportDate,
    String? resolvedAt,
  }) async {
    final body = <String, dynamic>{};
    if (notes != null) body['notes'] = notes;
    if (reportDate != null) body['report_date'] = reportDate;
    if (resolvedAt != null) body['resolved_at'] = resolvedAt;

    final res = await http.put(
      Uri.parse('${AppConfig.baseUrl}/system-status/$reportId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (res.statusCode == 409) {
      throw Exception(
          'An unresolved issue already exists for this system on that date');
    }
    if (res.statusCode != 200) {
      throw Exception('Failed to update issue');
    }

    final data = jsonDecode(res.body);
    return SystemStatusReport.fromJson(data['report']);
  }

  Future<void> deleteIssue({required String reportId}) async {
    final res = await http.delete(
      Uri.parse('${AppConfig.baseUrl}/system-status/$reportId'),
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to delete issue');
    }
  }

  Future<List<SystemUptimeReport>> fetchUptimeReport({
    required String startDate,
    required String endDate,
    String? systemName,
  }) async {
    final params = <String, String>{
      'start_date': startDate,
      'end_date': endDate,
    };
    if (systemName != null) params['system_name'] = systemName;

    final uri = Uri.parse('${AppConfig.baseUrl}/system-status/report')
        .replace(queryParameters: params);

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch uptime report');
    }

    final data = jsonDecode(res.body);
    return (data['systems'] as List)
        .map((j) => SystemUptimeReport.fromJson(j))
        .toList();
  }
}
