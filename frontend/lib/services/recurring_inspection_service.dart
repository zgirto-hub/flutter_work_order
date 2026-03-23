import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/recurring_inspection.dart';
import '../config.dart';

class RecurringInspectionService {
  String get _email =>
      Supabase.instance.client.auth.currentUser?.email ?? '';

  String get _userId =>
      Supabase.instance.client.auth.currentUser?.id ?? '';

  String _errorDetail(http.Response res, String fallback) {
    try {
      final body = jsonDecode(res.body);
      if (body is! Map) return fallback;
      final detail = body['detail'];
      if (detail is String) return detail;
      return fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<List<RecurringInspection>> fetchAll({bool? isActive}) async {
    final params = <String, String>{};
    if (isActive != null) params['is_active'] = isActive.toString();

    final uri = Uri.parse('${AppConfig.baseUrl}/recurring-inspections')
        .replace(queryParameters: params.isEmpty ? null : params);

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch recurring inspections');
    }
    final data = jsonDecode(res.body);
    return (data['recurring_inspections'] as List)
        .map((j) => RecurringInspection.fromJson(j))
        .toList();
  }

  Future<RecurringInspection> create({
    required String title,
    String description = '',
    String location = '',
    required String departmentId,
    required String frequency,
    int? dayOfWeek,
    int? dayOfMonth,
    int? interval,
    required String startDate,
    String? endDate,
    List<String> assignedFixerIds = const [],
  }) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/recurring-inspections'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'title': title,
        'description': description,
        'location': location,
        'department_id': departmentId,
        'frequency': frequency,
        'day_of_week': dayOfWeek,
        'day_of_month': dayOfMonth,
        'interval': interval,
        'start_date': startDate,
        'end_date': endDate,
        'assigned_fixer_ids': assignedFixerIds,
        'created_by': _userId,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to create recurring inspection'));
    }

    final data = jsonDecode(res.body);
    return RecurringInspection.fromJson(data['recurring_inspection']);
  }

  Future<RecurringInspection> update(String id, {
    required String title,
    String description = '',
    String location = '',
    required String departmentId,
    required String frequency,
    int? dayOfWeek,
    int? dayOfMonth,
    int? interval,
    required String startDate,
    String? endDate,
    bool isActive = true,
    List<String> assignedFixerIds = const [],
  }) async {
    final res = await http.put(
      Uri.parse('${AppConfig.baseUrl}/recurring-inspections/$id?user_email=${Uri.encodeComponent(_email)}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'title': title,
        'description': description,
        'location': location,
        'department_id': departmentId,
        'frequency': frequency,
        'day_of_week': dayOfWeek,
        'day_of_month': dayOfMonth,
        'interval': interval,
        'start_date': startDate,
        'end_date': endDate,
        'is_active': isActive,
        'assigned_fixer_ids': assignedFixerIds,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to update recurring inspection'));
    }

    final data = jsonDecode(res.body);
    return RecurringInspection.fromJson(data['recurring_inspection']);
  }

  Future<void> delete(String id) async {
    final res = await http.delete(
      Uri.parse('${AppConfig.baseUrl}/recurring-inspections/$id?user_email=${Uri.encodeComponent(_email)}'),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to delete recurring inspection'));
    }
  }

  Future<Map<String, dynamic>> generateDue() async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/recurring-inspections/generate'),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to generate inspections');
    }
    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> fetchCalendar(String startDate, String endDate) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/recurring-inspections/calendar')
        .replace(queryParameters: {
      'start_date': startDate,
      'end_date': endDate,
    });

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch calendar data');
    }
    return jsonDecode(res.body);
  }
}
