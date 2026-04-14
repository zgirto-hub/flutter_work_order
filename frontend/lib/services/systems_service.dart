import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';
import '../models/system.dart';

class SystemsService {
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

  Future<List<System>> fetchSystems({
    bool activeOnly = true,
    bool needsReview = false,
  }) async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final queryParams = [
      'user_email=${Uri.encodeComponent(userEmail)}',
      'active_only=$activeOnly',
      'needs_review=$needsReview',
    ].join('&');
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/systems?$queryParams'),
      headers: _headers(),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final systems = data['systems'] as List<dynamic>? ?? [];
      return systems.map((e) => System.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load systems');
    }
  }

  Future<System> createSystem({
    required String name,
    String? category,
    int? sortOrder,
  }) async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final res = await http.post(
      Uri.parse(
          '${AppConfig.baseUrl}/systems?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
      body: jsonEncode({
        'name': name,
        if (category != null) 'category': category,
        if (sortOrder != null) 'sort_order': sortOrder,
      }),
    );

    if (res.statusCode == 201) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return System.fromJson(data);
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else if (res.statusCode == 409) {
      throw Exception('System name already exists');
    } else {
      throw Exception('Failed to create system');
    }
  }

  Future<System> updateSystem(
    String id, {
    String? name,
    String? category,
    int? sortOrder,
  }) async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final res = await http.patch(
      Uri.parse(
          '${AppConfig.baseUrl}/systems/$id?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
      body: jsonEncode({
        if (name != null) 'name': name,
        if (category != null) 'category': category,
        if (sortOrder != null) 'sort_order': sortOrder,
      }),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return System.fromJson(data);
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else if (res.statusCode == 404) {
      throw Exception('System not found');
    } else if (res.statusCode == 409) {
      throw Exception('System name already exists');
    } else {
      throw Exception('Failed to update system');
    }
  }

  Future<Map<String, dynamic>> retireSystem(String id) async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final res = await http.patch(
      Uri.parse(
          '${AppConfig.baseUrl}/systems/$id/retire?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return {
        'system': System.fromJson(data['system']),
        if (data.containsKey('warning')) 'warning': data['warning'],
      };
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else if (res.statusCode == 404) {
      throw Exception('System not found');
    } else {
      throw Exception('Failed to retire system');
    }
  }

  Future<System> activateSystem(String id) async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final res = await http.patch(
      Uri.parse(
          '${AppConfig.baseUrl}/systems/$id/activate?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return System.fromJson(data);
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else if (res.statusCode == 404) {
      throw Exception('System not found');
    } else {
      throw Exception('Failed to activate system');
    }
  }
}
