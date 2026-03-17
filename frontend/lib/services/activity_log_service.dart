import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/activity_log_entry.dart';
import '../config.dart';

class ActivityLogService {
  Future<List<ActivityLogEntry>> fetchLogs({
    String? category,
    int limit = 100,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (category != null && category != 'all') {
      params['category'] = category;
    }

    final uri = Uri.parse('${AppConfig.baseUrl}/activity-log')
        .replace(queryParameters: params);

    final res = await http.get(uri);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return (data['logs'] as List)
          .map((j) => ActivityLogEntry.fromJson(j))
          .toList();
    }
    return [];
  }

  Future<void> logSignIn(String email) async {
    try {
      await http.post(
        Uri.parse('${AppConfig.baseUrl}/activity-log/sign-in'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_email': email}),
      );
    } catch (_) {}
  }

  Future<void> logSignOut(String email) async {
    try {
      await http.post(
        Uri.parse('${AppConfig.baseUrl}/activity-log/sign-out'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_email': email}),
      );
    } catch (_) {}
  }
}
