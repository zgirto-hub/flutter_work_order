import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';

class SettingsService {
  String get _email => Supabase.instance.client.auth.currentUser?.email ?? '';

  Future<Map<String, dynamic>> getSetting(String key) async {
    final res = await http.get(
      Uri.parse(
          '${AppConfig.baseUrl}/settings/$key?admin_email=${Uri.encodeComponent(_email)}'),
      headers: {'Content-Type': 'application/json'},
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } else if (res.statusCode == 404) {
      return {};
    } else {
      throw Exception('Failed to get setting: ${res.body}');
    }
  }

  Future<Map<String, dynamic>> updateSetting(String key, String value) async {
    final res = await http.put(
      Uri.parse(
          '${AppConfig.baseUrl}/settings/$key?admin_email=${Uri.encodeComponent(_email)}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'value': value}),
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to update setting: ${res.body}');
    }
  }
}
