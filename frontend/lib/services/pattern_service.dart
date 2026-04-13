import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';
import '../models/pattern_rule.dart';
import '../models/pattern_alert.dart';

class PatternService {
  Map<String, String> _headers() {
    final session = Supabase.instance.client.auth;
    final token = session.currentSession?.accessToken;
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<List<PatternRule>> getRules() async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/patterns/rules'),
      headers: _headers(),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final rules = data['rules'] as List<dynamic>? ?? [];
      return rules.map((e) => PatternRule.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load rules');
    }
  }

  Future<PatternRule> createRule(
      Map<String, dynamic> body, String userEmail) async {
    final res = await http.post(
      Uri.parse(
          '${AppConfig.baseUrl}/patterns/rules?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
      body: jsonEncode(body),
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      return PatternRule.fromJson(jsonDecode(res.body));
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else {
      final err = jsonDecode(res.body);
      throw Exception(err['detail'] ?? 'Failed to create rule');
    }
  }

  Future<PatternRule> updateRule(
      String ruleId, Map<String, dynamic> body, String userEmail) async {
    final res = await http.put(
      Uri.parse(
          '${AppConfig.baseUrl}/patterns/rules/$ruleId?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
      body: jsonEncode(body),
    );

    if (res.statusCode == 200) {
      return PatternRule.fromJson(jsonDecode(res.body));
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else if (res.statusCode == 404) {
      throw Exception('Rule not found');
    } else {
      final err = jsonDecode(res.body);
      throw Exception(err['detail'] ?? 'Failed to update rule');
    }
  }

  Future<void> deleteRule(String ruleId, String userEmail) async {
    final res = await http.delete(
      Uri.parse(
          '${AppConfig.baseUrl}/patterns/rules/$ruleId?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
    );

    if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else if (res.statusCode == 404) {
      throw Exception('Rule not found');
    } else if (res.statusCode != 200) {
      throw Exception('Failed to delete rule');
    }
  }

  Future<PatternRule> toggleRule(String ruleId, String userEmail) async {
    final res = await http.patch(
      Uri.parse(
          '${AppConfig.baseUrl}/patterns/rules/$ruleId/toggle?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
    );

    if (res.statusCode == 200) {
      return PatternRule.fromJson(jsonDecode(res.body));
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else if (res.statusCode == 404) {
      throw Exception('Rule not found');
    } else {
      throw Exception('Failed to toggle rule');
    }
  }

  Future<Map<String, dynamic>> getAlerts({
    required String userEmail,
    String? status,
    String? severity,
    int page = 1,
    int pageSize = 20,
  }) async {
    final queryParams = <String, String>{
      'user_email': userEmail,
      'page': page.toString(),
      'page_size': pageSize.toString(),
    };
    if (status != null) queryParams['status'] = status;
    if (severity != null) queryParams['severity'] = severity;

    final uri = Uri.parse('${AppConfig.baseUrl}/patterns/alerts')
        .replace(queryParameters: queryParams);

    final res = await http.get(uri, headers: _headers());

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final alerts = (data['alerts'] as List<dynamic>?)
              ?.map((e) => PatternAlert.fromJson(e))
              .toList() ??
          [];
      return {
        'alerts': alerts,
        'total': data['total'] as int? ?? 0,
        'page': data['page'] as int? ?? 1,
        'page_size': data['page_size'] as int? ?? 20,
      };
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else {
      throw Exception('Failed to load alerts');
    }
  }

  Future<PatternAlert> updateAlertStatus(
      String alertId, String status, String userEmail) async {
    final res = await http.patch(
      Uri.parse(
          '${AppConfig.baseUrl}/patterns/alerts/$alertId/status?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
      body: jsonEncode({'status': status}),
    );

    if (res.statusCode == 200) {
      return PatternAlert.fromJson(jsonDecode(res.body));
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else if (res.statusCode == 404) {
      throw Exception('Alert not found');
    } else if (res.statusCode == 400) {
      final err = jsonDecode(res.body);
      throw Exception(err['detail'] ?? 'Invalid status transition');
    } else {
      throw Exception('Failed to update alert status');
    }
  }

  Future<Map<String, dynamic>> triggerScan(String userEmail) async {
    final res = await http.post(
      Uri.parse(
          '${AppConfig.baseUrl}/patterns/scan?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else {
      throw Exception('Failed to trigger scan');
    }
  }
}
